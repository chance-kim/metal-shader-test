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
    var imagePipelineState: MTLRenderPipelineState!
    
    var renderTargetTexture: MTLTexture?
    var renderPassDescriptor: MTLRenderPassDescriptor!
    var renderPipelineState: MTLRenderPipelineState!
    
    var imageTexture: MTLTexture?
    var maskingTexture: MTLTexture?
    var imageDepthState:MTLDepthStencilState!
    
    var imageVertexFunction: MTLFunction!
    var imageFragmentFunction: MTLFunction!
    var renderTargetFragmentFunction: MTLFunction!
    
    
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
        imageFragmentFunction = defaultLibrary.makeFunction(name: "swapFragmentFunction")
        renderTargetFragmentFunction = defaultLibrary.makeFunction(name: "imageFragmentFunction")
        
        self.commandQueue = self.device.makeCommandQueue()
        
        let size = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imageVertexBuffer = self.device.makeBuffer(bytes: kImagePlaneVertexData, length: size)
        imageVertexBuffer.label = "ImageVertexBuffer"
        
        
        initRederTarget()
        initSwapRender()
        
        self.imageTexture = loadTexture(name:"sample", ext:"png")
        self.maskingTexture = loadTexture(name: "masking", ext: "png")
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
        
        
        let imagePipelineDescriptor = MTLRenderPipelineDescriptor()
        imagePipelineDescriptor.label = "ImageRenderPipeline"
        imagePipelineDescriptor.sampleCount = 1
        imagePipelineDescriptor.vertexFunction = imageVertexFunction
        imagePipelineDescriptor.fragmentFunction = renderTargetFragmentFunction
        imagePipelineDescriptor.vertexDescriptor = imageVertexDescriptor
        imagePipelineDescriptor.depthAttachmentPixelFormat = .invalid
        imagePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            try self.renderPipelineState = self.device.makeRenderPipelineState(descriptor: imagePipelineDescriptor)
        } catch let error {
            print("error=\(error.localizedDescription)")
        }
        
        let texDescriptor = MTLTextureDescriptor()
        texDescriptor.textureType = MTLTextureType.type2D
        texDescriptor.width = 56
        texDescriptor.height = 56
        texDescriptor.pixelFormat = .bgra8Unorm
        texDescriptor.storageMode = .shared
        texDescriptor.usage = [.renderTarget, .shaderRead]
        
        self.renderTargetTexture = self.device.makeTexture(descriptor: texDescriptor)
        
        let clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        self.renderPassDescriptor = MTLRenderPassDescriptor()
        self.renderPassDescriptor.colorAttachments[0].texture = self.renderTargetTexture
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
        imagePipelineDescriptor.fragmentFunction = imageFragmentFunction
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
        commandBuffer.addCompletedHandler{
            _ in
            let endTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            print("complete: \(endTime - startTime)ms)")
        }
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderPassDescriptor) else {
            return
        }
        
        
        renderEncoder.label = "RenderEncoder"
        renderEncoder.setCullMode(.front)
        renderEncoder.setRenderPipelineState(self.renderPipelineState)
        renderEncoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(self.imageTexture!, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        
        guard let swapEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return
        }
        swapEncoder.label = "SwapEncoder"
        swapEncoder.setCullMode(.front)
        swapEncoder.setRenderPipelineState(self.imagePipelineState)
        swapEncoder.setDepthStencilState(self.imageDepthState)
        swapEncoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
        swapEncoder.setFragmentTexture(self.renderTargetTexture, index: 0)
        swapEncoder.setFragmentTexture(self.imageTexture, index: 1)
        swapEncoder.setFragmentTexture(self.maskingTexture, index: 2)
        
        swapEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        swapEncoder.endEncoding()
        
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension Renderer:MTKViewDelegate {
    func draw(in view: MTKView) {
        self.render(view: view)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}
