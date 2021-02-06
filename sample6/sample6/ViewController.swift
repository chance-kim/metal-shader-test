//
//  ViewController.swift
//  sample6
//
//  Created by chance.k on 2021/02/06.
//

import UIKit
import MetalKit

class ViewController: UIViewController {

    @IBOutlet weak var mtkView: MTKView!
    
    var renderer:Renderer = .init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.mtkView.enableSetNeedsDisplay = true
        self.mtkView.device = self.renderer.device
        self.mtkView.delegate = self.renderer
    }

}
