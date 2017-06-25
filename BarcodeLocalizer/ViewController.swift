//
//  ViewController.swift
//  BarcodeLocalizer
//
//  Created by Luca Torella on 25.06.17.
//  Copyright © 2017 Luca Torella. All rights reserved.
//

import AVFoundation
import Vision
import UIKit

class ViewController: UIViewController {

    private var requests = [VNRequest]()
    private let session = AVCaptureSession()
    private lazy var drawLayer: CAShapeLayer = {
        let shapeLayer = CAShapeLayer()
        self.view.layer.addSublayer(shapeLayer)
        shapeLayer.frame = self.view.bounds
        return shapeLayer
    }()
    private let bufferQueue = DispatchQueue(label: "com.lucatorella.BufferQueue",
                                            qos: .userInteractive,
                                            attributes: .concurrent)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupVision()
    }

    // MARK: - Vision

    func setupVision() {
        let barcodeRequest = VNDetectBarcodesRequest(completionHandler: barcodeDetectionHandler)
        barcodeRequest.symbologies = [.QR] // VNDetectBarcodesRequest.supportedSymbologies
        self.requests = [barcodeRequest]
    }

    func barcodeDetectionHandler(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }

        DispatchQueue.main.async() {
            // Loop through the results found.
            let path = CGMutablePath()

            for result in results {
                guard let barcode = result as? VNBarcodeObservation else { continue }
                let topLeft = self.convert(point: barcode.topLeft)
                path.move(to: topLeft)
                let topRight = self.convert(point: barcode.topRight)
                path.addLine(to: topRight)
                let bottomRight = self.convert(point: barcode.bottomRight)
                path.addLine(to: bottomRight)
                let bottomLeft = self.convert(point: barcode.bottomLeft)
                path.addLine(to: bottomLeft)
                path.addLine(to: topLeft)
            }

            self.drawLayer.path = path
            self.drawLayer.strokeColor = UIColor.blue.cgColor
            self.drawLayer.lineWidth = 1
            self.drawLayer.lineJoin = kCALineJoinRound
            self.drawLayer.fillColor = UIColor.clear.cgColor
        }
    }

    private func convert(point: CGPoint) -> CGPoint {
        return CGPoint(x: point.x * view.bounds.size.width,
                       y: (1 - point.y) * view.bounds.size.height)
    }

    // MARK: - Setup Camera

    func setupCamera() {
        let availableCameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                                      mediaType: .video,
                                                                      position: .back)

        guard let activeDevice = (availableCameraDevices.devices.first { $0.position == .back }) else {
            return
        }

        do {
            let deviceInput = try AVCaptureDeviceInput(device: activeDevice)
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
        } catch {
            print("no camera")
        }

        guard cameraAuthorization() else {return}

        let videoOutput = AVCaptureVideoDataOutput()

        videoOutput.setSampleBufferDelegate(self, queue: bufferQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)

        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        session.startRunning()
    }

    private func cameraAuthorization() -> Bool{
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.view.setNeedsDisplay()
                    }
                }
            }
            return true
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var requestOptions: [VNImageOption: Any] = [:]

        if let data = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: data]
        }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: 6, options: requestOptions)

        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
}
