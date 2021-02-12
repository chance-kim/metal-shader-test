//
//  ViewController.swift
//  sample9
//
//  Created by chance.k on 2021/02/12.
//

import UIKit
import MetalKit
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet weak var mtkView: MTKView!
    
    let camera = Camera()
    var renderer:Renderer = .init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.mtkView.isPaused = true
        self.mtkView.enableSetNeedsDisplay = false
        self.mtkView.device = self.renderer.device
        self.mtkView.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.camera.setSampleBufferDelegate(self)
        self.camera.start()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.camera.stop()
    }
}

extension ViewController:MTKViewDelegate {
    func draw(in view: MTKView) {

        self.renderer.renderToDraw(view: view)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = .portrait
        //let scale:Float64 = 1_000_000
        //let time = Int64( CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * scale)
        
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            if self.renderer.renderToTransform(pixelBuffer) == true {
                self.mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
                self.mtkView.draw()
            }
        }
    }
}





class Camera: NSObject {
    lazy var session: AVCaptureSession = .init()
    lazy var input: AVCaptureDeviceInput = try! AVCaptureDeviceInput(device: device)
    lazy var device: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)!
    lazy var output: AVCaptureVideoDataOutput = .init()
    
    override init() {
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
        
        session.addInput(input)
        session.addOutput(output)
    }
    
    func setSampleBufferDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        output.setSampleBufferDelegate(delegate, queue: .main)
    }
    
    func start() {
        session.startRunning()
    }
    
    func stop() {
        session.stopRunning()
    }
}
