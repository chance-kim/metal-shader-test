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
    
    var imageVertexBuffer: MTLBuffer!
    var sharedDataBuffer: MTLBuffer!
    var imagePipelineState: MTLRenderPipelineState!
    
    // 두개의 텍스처 및 렌더패스
    // 가로
    var renderHTargetTexture: MTLTexture?
    var renderHPassDescriptor: MTLRenderPassDescriptor!
    var renderHPipelineState: MTLRenderPipelineState!
    
    // 세로
    var renderVTargetTexture: MTLTexture?
    var renderVPassDescriptor: MTLRenderPassDescriptor!
    var renderVPipelineState: MTLRenderPipelineState!
    
    // 입력 이미지
    var imageTexture: MTLTexture?
    var imageDepthState:MTLDepthStencilState!
    
    // 화면 렌더링 쉐이더
    var imageVertexFunction: MTLFunction!
    var renderScreenFragmentFunction: MTLFunction!
    
    // 가로방향, 세로방향 쉐이더
    var renderHTextureFragmentFunction: MTLFunction!
    var renderVTextureFragmentFunction: MTLFunction!
    
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
        renderHTextureFragmentFunction = defaultLibrary.makeFunction(name: "imageHFragmentFunction")
        renderVTextureFragmentFunction = defaultLibrary.makeFunction(name: "imageVFragmentFunction")
        
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
        initGaussianFilter()
        
        self.imageTexture = loadTexture(name:"sample", ext:"png")
    }
    

    func initGaussianFilter() {
        // 쉐이더에 공통적으로 전달할 데이터 생성
        // 시그마에 따른 가우시안
        let SIGMA = 4.0     // sigma^2
        let PI2 = 6.28319 // 2pi
        let TAP = 7
        
        let data = self.sharedDataBuffer.contents().assumingMemoryBound(to: SharedData.self)
        data.pointee.tapCount = Float(TAP)
        
        var total:Double = 0
        var result = [Double](repeating: 0.0, count: TAP)
        for i in 0..<TAP {
            let x = Double(i - (TAP - 1) / 2)
            result[i] = (1 / sqrtl(PI2 * SIGMA))*(expl( -(x*x) / (2*SIGMA)))
            print("\(x)=\(result[i])")
            total += result[i]
        }
        print("total=\(total)")
        
        withUnsafeMutablePointer(to: &data.pointee.gaussian) { pointer in
            pointer.withMemoryRebound(to: Float.self, capacity: TAP) { buffer in
                var index = 0
                for value in result {
                    buffer[index] = Float(value) / Float(total)
                    index += 1
                }
            }
        }
        
        print("\(data.pointee.gaussian)")
    }
    
    func initRederTarget() {
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
        
        
        let imageHPipelineDescriptor = MTLRenderPipelineDescriptor()
        imageHPipelineDescriptor.label = "ImageHRenderPipeline"
        imageHPipelineDescriptor.sampleCount = 1
        imageHPipelineDescriptor.vertexFunction = imageVertexFunction
        imageHPipelineDescriptor.fragmentFunction = renderHTextureFragmentFunction
        imageHPipelineDescriptor.vertexDescriptor = imageVertexDescriptor
        imageHPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        imageHPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            try self.renderHPipelineState = self.device.makeRenderPipelineState(descriptor: imageHPipelineDescriptor)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
        
        let imageVPipelineDescriptor = MTLRenderPipelineDescriptor()
        imageVPipelineDescriptor.label = "ImageVRenderPipeline"
        imageVPipelineDescriptor.sampleCount = 1
        imageVPipelineDescriptor.vertexFunction = imageVertexFunction
        imageVPipelineDescriptor.fragmentFunction = renderVTextureFragmentFunction
        imageVPipelineDescriptor.vertexDescriptor = imageVertexDescriptor
        imageVPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        imageVPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            try self.renderVPipelineState = self.device.makeRenderPipelineState(descriptor: imageVPipelineDescriptor)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
        
        
        let texDescriptor = MTLTextureDescriptor()
        texDescriptor.textureType = MTLTextureType.type2D
        texDescriptor.width = 256
        texDescriptor.height = 256
        texDescriptor.pixelFormat = .bgra8Unorm
        texDescriptor.storageMode = .private
        texDescriptor.usage = [.renderTarget, .shaderRead]
        
        self.renderHTargetTexture = self.device.makeTexture(descriptor: texDescriptor)
        self.renderVTargetTexture = self.device.makeTexture(descriptor: texDescriptor)
        
        let clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        self.renderHPassDescriptor = MTLRenderPassDescriptor()
        self.renderHPassDescriptor.colorAttachments[0].texture = self.renderHTargetTexture
        self.renderHPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderHPassDescriptor.colorAttachments[0].clearColor = clearColor
        self.renderHPassDescriptor.colorAttachments[0].storeAction = .store
        
        
        self.renderVPassDescriptor = MTLRenderPassDescriptor()
        self.renderVPassDescriptor.colorAttachments[0].texture = self.renderVTargetTexture
        self.renderVPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderVPassDescriptor.colorAttachments[0].clearColor = clearColor
        self.renderVPassDescriptor.colorAttachments[0].storeAction = .store
        
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
    
    
    
    func render(view:MTKView) {
        print("render")
        let startTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        guard let renderPass = view.currentRenderPassDescriptor else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "RenderCommand"
        
        
        // 블러 추가
        for i in 0..<5 {
            var inputTexture = self.renderVTargetTexture
            if i == 0 {
                inputTexture = self.imageTexture
            }
            
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderHPassDescriptor)  {
                encoder.label = "RenderHEncoder"
                encoder.setCullMode(.front)
                encoder.setRenderPipelineState(self.renderHPipelineState)
                encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(inputTexture, index: 0)
                encoder.setFragmentBuffer(self.sharedDataBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }
            
            
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderVPassDescriptor)  {
                encoder.label = "RenderVEncoder"
                encoder.setCullMode(.front)
                encoder.setRenderPipelineState(self.renderVPipelineState)
                encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(self.renderHTargetTexture!, index: 0)
                encoder.setFragmentBuffer(self.sharedDataBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }
        }
            

        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            encoder.label = "SwapEncoder"
            encoder.setCullMode(.front)
            encoder.setRenderPipelineState(self.imagePipelineState)
            encoder.setDepthStencilState(self.imageDepthState)
            encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(self.renderVTargetTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        
        
        
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let endTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        print("complete: \(endTime - startTime)ms)")
    }
}

extension Renderer:MTKViewDelegate {
    func draw(in view: MTKView) {
        self.render(view: view)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}
