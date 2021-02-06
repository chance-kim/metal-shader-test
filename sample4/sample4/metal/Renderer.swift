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
    var imageDepthState:MTLDepthStencilState!
    
    var imageVertexFunction: MTLFunction!
    var renderScreenFragmentFunction: MTLFunction!
    var renderTextureFragmentFunction: MTLFunction!
    
    
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
        renderTextureFragmentFunction = defaultLibrary.makeFunction(name: "imageFragmentFunction")
        renderScreenFragmentFunction = defaultLibrary.makeFunction(name: "swapFragmentFunction")
        
        
        self.commandQueue = self.device.makeCommandQueue()
        
        let size = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imageVertexBuffer = self.device.makeBuffer(bytes: kImagePlaneVertexData, length: size)
        imageVertexBuffer.label = "ImageVertexBuffer"
        
        
        initRederTarget()
        initSwapRender()
        
        self.imageTexture = loadTexture(name:"sample", ext:"png")
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
        imagePipelineDescriptor.fragmentFunction = renderTextureFragmentFunction
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
        
        guard let renderPass = view.currentRenderPassDescriptor else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "RenderCommand"
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderPassDescriptor) {
            encoder.label = "RenderEncoder"
            encoder.setCullMode(.front)
            encoder.setRenderPipelineState(self.renderPipelineState)
            encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(self.imageTexture!, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            encoder.label = "SwapEncoder"
            encoder.setCullMode(.front)
            encoder.setRenderPipelineState(self.imagePipelineState)
            encoder.setDepthStencilState(self.imageDepthState)
            encoder.setVertexBuffer(self.imageVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(self.renderTargetTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        
        
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
