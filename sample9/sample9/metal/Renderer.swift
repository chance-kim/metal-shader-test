//
//  Renderer.swift
//  blur-shader
//
//  Created by chance.k on 2021/02/03.
//

import Foundation
import MetalKit


let kImagePlaneVertexData:[Float] = [
    -1.0, -1.0, 0.0, 1.0,
    1.0, -1.0, 1.0, 1.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, 1.0, 1.0, 0.0,
]



class Renderer:NSObject {
    var device:MTLDevice!
    
    var commandQueue: MTLCommandQueue!
    var sharedDataPtr: UnsafeMutablePointer<SharedData>?
    
    var imageVertexBuffer: MTLBuffer!
    var sharedDataBuffer: MTLBuffer!
    var imagePipelineState: MTLRenderPipelineState!
    var imageDepthState:MTLDepthStencilState!
    
    
    // gaussian working texture
    var workHTargetTexture: MTLTexture?
    var workVTargetTexture: MTLTexture?

    // transform render target render pass
    var imageResizeTexture: MTLTexture?
    var renderPassDescriptor: MTLRenderPassDescriptor!
    var renderPipelineState: MTLRenderPipelineState!
    
    // input texture
    var textureCache: CVMetalTextureCache?
    var cameraTexture: CVMetalTexture?
    
   
    // masking texture
    var maskingTexture: MTLTexture?
   
    // shader functions
    var imageVertexFunction: MTLFunction!
    var renderScreenFragmentFunction: MTLFunction!
    var renderTextureFragmentFunction: MTLFunction!
    
    // gaussian compute pipeline and shader functions
    var computeHPipelineState: MTLComputePipelineState!
    var computeVPipelineState: MTLComputePipelineState!
    var computeHFunction: MTLFunction!
    var computeVFunction: MTLFunction!
    
    override init() {
        super.init()
        
        self.device = MTLCreateSystemDefaultDevice()
        initMetal()
    }
    
    func initMetal() {
        guard let defaultLibrary = try? self.device.makeDefaultLibrary(bundle: Bundle(for: Renderer.self)) else {
            print("[Renderer.initMetal] init error")
            return
        }
        
        imageVertexFunction = defaultLibrary.makeFunction(name: "imageVertexFunction")
        renderScreenFragmentFunction = defaultLibrary.makeFunction(name: "swapFragmentFunction")
        renderTextureFragmentFunction = defaultLibrary.makeFunction(name: "imageResizeFragmentFunction")
        computeHFunction = defaultLibrary.makeFunction(name: "gaussianBlurHFunction")
        computeVFunction = defaultLibrary.makeFunction(name: "gaussianBlurVFunction")
        
        self.commandQueue = self.device.makeCommandQueue()
        
        let size = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imageVertexBuffer = self.device.makeBuffer(bytes: kImagePlaneVertexData, length: size)
        imageVertexBuffer.label = "ImageVertexBuffer"
        
        // 공유데이터 버퍼
        let sharedBufferSize = (MemoryLayout<SharedData>.size & ~0xFF) + 0x100
        sharedDataBuffer = self.device.makeBuffer(length: sharedBufferSize, options: .storageModeShared)
        sharedDataBuffer.label = "SharedBuffer"
        
        
        
        initRederTarget()
        initSwapRender()
        initKernelTarget()
        initGaussianFilter()
        
        self.maskingTexture = loadTexture(name:"masking", ext:"png")
    }
    

    func initGaussianFilter() {
        // 쉐이더에 공통적으로 전달할 데이터 생성
        // 시그마에 따른 가우시안
        let SIGMA = 4.0     // sigma^2
        let PI2 = 6.28319 // 2pi
        let TAP = 7
        
        self.sharedDataPtr = self.sharedDataBuffer.contents().assumingMemoryBound(to: SharedData.self)
        if let ptr = self.sharedDataPtr {
            ptr.pointee.tapCount = Float(TAP)
            
            var total:Double = 0
            var result = [Double](repeating: 0.0, count: TAP)
            for i in 0..<TAP {
                let x = Double(i - (TAP - 1) / 2)
                result[i] = (1 / sqrtl(PI2 * SIGMA))*(expl( -(x*x) / (2*SIGMA)))
                print("\(x)=\(result[i])")
                total += result[i]
            }
            print("total=\(total)")
            
            withUnsafeMutablePointer(to: &ptr.pointee.gaussian) { pointer in
                pointer.withMemoryRebound(to: Float.self, capacity: TAP) { buffer in
                    var index = 0
                    for value in result {
                        buffer[index] = Float(value) / Float(total)
                        index += 1
                    }
                }
            }
            
            print("\(ptr.pointee.gaussian)")
        }
    }
    
    func initKernelTarget() {
        do {
            try self.computeHPipelineState = self.device.makeComputePipelineState(function: self.computeHFunction)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
        
        
        do {
            try self.computeVPipelineState = self.device.makeComputePipelineState(function: self.computeVFunction)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
    }
    
    func initRederTarget() {
        // texture cache
        CVMetalTextureCacheCreate(nil, nil, device, nil, &self.textureCache)
        
        
        let imageVertexDescriptor = MTLVertexDescriptor()
        imageVertexDescriptor.attributes[0].format = .float2
        imageVertexDescriptor.attributes[0].offset = 0
        imageVertexDescriptor.attributes[0].bufferIndex = 0
        imageVertexDescriptor.attributes[1].format = .float2
        imageVertexDescriptor.attributes[1].offset = 8
        imageVertexDescriptor.attributes[1].bufferIndex = 0
        imageVertexDescriptor.layouts[0].stride = 16
        imageVertexDescriptor.layouts[0].stepRate = 1
        imageVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        
        let imagePipelineDescriptor = MTLRenderPipelineDescriptor()
        imagePipelineDescriptor.label = "ImageResizeRenderPipeline"
        imagePipelineDescriptor.sampleCount = 1
        imagePipelineDescriptor.vertexFunction = imageVertexFunction
        imagePipelineDescriptor.fragmentFunction = renderTextureFragmentFunction
        imagePipelineDescriptor.vertexDescriptor = imageVertexDescriptor
        imagePipelineDescriptor.depthAttachmentPixelFormat = .invalid
        imagePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            try self.renderPipelineState = self.device.makeRenderPipelineState(descriptor: imagePipelineDescriptor)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
        
        
        // first transform texture (render target)
        let texDescriptor = MTLTextureDescriptor()
        texDescriptor.textureType = MTLTextureType.type2D
        texDescriptor.width = 256
        texDescriptor.height = 256
        texDescriptor.pixelFormat = .bgra8Unorm
        texDescriptor.storageMode = .private
        texDescriptor.usage = [.renderTarget, .shaderRead]
        self.imageResizeTexture = self.device.makeTexture(descriptor: texDescriptor)
        
        
        // gaussian working texture
        let tex2Descriptor = MTLTextureDescriptor()
        tex2Descriptor.textureType = MTLTextureType.type2D
        tex2Descriptor.width = 256
        tex2Descriptor.height = 256
        tex2Descriptor.pixelFormat = .bgra8Unorm
        tex2Descriptor.storageMode = .private
        tex2Descriptor.usage = [.shaderRead, .shaderWrite]
        
        
        self.workHTargetTexture = self.device.makeTexture(descriptor: tex2Descriptor)
        self.workVTargetTexture = self.device.makeTexture(descriptor: tex2Descriptor)
        
        let clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        self.renderPassDescriptor = MTLRenderPassDescriptor()
        self.renderPassDescriptor.colorAttachments[0].texture = self.imageResizeTexture
        self.renderPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        self.renderPassDescriptor.colorAttachments[0].storeAction = .store
    }
    
    
    func initSwapRender() {
        let imageVertexDescriptor = MTLVertexDescriptor()
        imageVertexDescriptor.attributes[0].format = .float2
        imageVertexDescriptor.attributes[0].offset = 0
        imageVertexDescriptor.attributes[0].bufferIndex = 0
        imageVertexDescriptor.attributes[1].format = .float2
        imageVertexDescriptor.attributes[1].offset = 8
        imageVertexDescriptor.attributes[1].bufferIndex = 0
        imageVertexDescriptor.layouts[0].stride = 16
        imageVertexDescriptor.layouts[0].stepRate = 1
        imageVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        
        let imagePipelineDescriptor = MTLRenderPipelineDescriptor()
        imagePipelineDescriptor.label = "ImageRenderPipeline"
        imagePipelineDescriptor.sampleCount = 1
        imagePipelineDescriptor.vertexFunction = imageVertexFunction
        imagePipelineDescriptor.fragmentFunction = renderScreenFragmentFunction
        imagePipelineDescriptor.vertexDescriptor = imageVertexDescriptor
        imagePipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        imagePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            try self.imagePipelineState = self.device.makeRenderPipelineState(descriptor: imagePipelineDescriptor)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
        
        // depth state
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        self.imageDepthState = self.device.makeDepthStencilState(descriptor: depthDescriptor)
    }
    
    func loadTexture(name:String, ext:String) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: device)
        if let url = Bundle(for: Renderer.self).url(forResource: name, withExtension: ext) {
            let texture = try? textureLoader.newTexture(URL: url , options: nil)
            return texture
        }
        return nil
    }
    

    
    func renderToTransform(_ pixelBuffer:CVPixelBuffer ) -> Bool {
        // resize, rgba transform, render to texture
        let startTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else { return false }
        commandBuffer.label = "RenderCommand1"

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let status = CVMetalTextureCacheCreateTextureFromImage(
                              nil,
                              self.textureCache!,
                              pixelBuffer,
                              nil,
                              .bgra8Unorm,
                              width,
                              height,
                              0,
                              &self.cameraTexture)
        if status != kCVReturnSuccess {
            return false
        }
        
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderPassDescriptor)  {
            encoder.label = "RenderResizeEncoder"
            encoder.setCullMode(.front)
            encoder.setRenderPipelineState(self.renderPipelineState)
            encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(CVMetalTextureGetTexture(self.cameraTexture!), index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let endTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        print("complete: \(endTime - startTime)ms)")
        return true
        
    }
    
    func renderToDraw(view:MTKView) {
        let startTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        guard let renderPass = view.currentRenderPassDescriptor else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "RenderCommand2"
    

        // 블러
        let threadGroupCount = MTLSizeMake(16, 16, 1)
        let threadCountPerGroup = MTLSizeMake(
            self.workHTargetTexture!.width / threadGroupCount.width,
            self.workHTargetTexture!.height / threadGroupCount.height,
            1)
        
        for i in 0...5 {
            var inputTexture:MTLTexture = self.workVTargetTexture!
            if i == 0 {
                inputTexture = self.imageResizeTexture!
            }
                
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(self.computeHPipelineState)
                encoder.setTexture(inputTexture, index: 0)
                encoder.setTexture(self.workHTargetTexture, index: 1)
                encoder.setBuffer(self.sharedDataBuffer, offset: 0, index: 0)
                encoder.dispatchThreadgroups(threadCountPerGroup, threadsPerThreadgroup: threadGroupCount)
                encoder.endEncoding()
            }
            
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(self.computeVPipelineState)
                encoder.setTexture(self.workHTargetTexture, index: 0)
                encoder.setTexture(self.workVTargetTexture, index: 1)
                encoder.setBuffer(self.sharedDataBuffer, offset: 0, index: 0)
                encoder.dispatchThreadgroups(threadCountPerGroup, threadsPerThreadgroup: threadGroupCount)
                encoder.endEncoding()
            }
        }
        
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            encoder.label = "SwapEncoder"
            encoder.setCullMode(.front)
            encoder.setRenderPipelineState(self.imagePipelineState)
            encoder.setDepthStencilState(self.imageDepthState)
            encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(CVMetalTextureGetTexture(self.cameraTexture!), index: 0)
            encoder.setFragmentTexture(self.workVTargetTexture, index: 1)
            encoder.setFragmentTexture(self.maskingTexture!, index: 2)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        self.cameraTexture = nil
        let endTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        print("complete: \(endTime - startTime)ms)")
    }
}
