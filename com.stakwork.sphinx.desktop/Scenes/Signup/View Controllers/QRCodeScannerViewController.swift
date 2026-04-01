//
//  QRCodeScannerViewController.swift
//  Sphinx
//
//  Created for seed import QR code scanning.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa
import AVFoundation
import CoreImage

@MainActor
protocol QRCodeScannerDelegate: AnyObject {
    func didScanQRCode(string: String)
}

class QRCodeScannerViewController: NSViewController {

    weak var delegate: QRCodeScannerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didDetect = false

    private lazy var qrDetector: CIDetector? = {
        return CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }()

    // MARK: - View Lifecycle

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCancelButton()
        requestCameraAccess()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        stopSession()
    }

    // MARK: - UI Setup

    private func setupCancelButton() {
        let primaryBlue = NSColor(red: 0.380, green: 0.541, blue: 1.0, alpha: 1.0)

        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        let backgroundBox = NSBox()
        backgroundBox.boxType = .custom
        backgroundBox.borderType = .lineBorder
        backgroundBox.cornerRadius = 24
        backgroundBox.titlePosition = .noTitle
        backgroundBox.fillColor = primaryBlue
        backgroundBox.borderColor = NSColor.clear
        backgroundBox.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(backgroundBox)

        let label = NSTextField(labelWithString: "cancel".localized)
        label.font = NSFont(name: "Roboto-Regular", size: 13) ?? NSFont.systemFont(ofSize: 13)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        backgroundBox.addSubview(label)

        let cancelButton = CustomButton()
        cancelButton.isBordered = false
        cancelButton.title = ""
        cancelButton.bezelStyle = .shadowlessSquare
        cancelButton.isTransparent = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.cursor = .pointingHand
        containerView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            containerView.widthAnchor.constraint(equalToConstant: 136),
            containerView.heightAnchor.constraint(equalToConstant: 50),

            backgroundBox.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            backgroundBox.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            backgroundBox.topAnchor.constraint(equalTo: containerView.topAnchor),
            backgroundBox.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: backgroundBox.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: backgroundBox.centerYAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cancelButton.topAnchor.constraint(equalTo: containerView.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    // MARK: - Camera

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.configureSession()
                } else {
                    self?.showNoCameraAlert()
                }
            }
        }
    }

    private func configureSession() {
        // Try .front first (matches the LiveKit usage pattern), fall back to any available camera
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                  ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                  ?? AVCaptureDevice.default(for: .video)

        guard let device = device else {
            showNoCameraAlert()
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                showNoCameraAlert()
                return
            }
            session.addInput(input)
        } catch {
            showNoCameraAlert()
            return
        }

        // Use AVCaptureVideoDataOutput + CIDetector for QR scanning — this is the
        // correct macOS approach (AVCaptureMetadataOutput .qr is iOS-primary and
        // unreliable on macOS).
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "qr.scanner.queue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(videoOutput) else {
            showNoCameraAlert()
            return
        }
        session.addOutput(videoOutput)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer?.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer

        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        previewLayer?.frame = view.bounds
    }

    func stopSession() {
        DispatchQueue.global().async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    private func showNoCameraAlert() {
        AlertHelper.showAlert(
            title: "Error",
            message: "no.camera.available".localized
        )
        dismiss(self)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        stopSession()
        dismiss(self)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension QRCodeScannerViewController: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Skip frames once a code has been detected
        guard !didDetect else { return }

        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let features = qrDetector?.features(in: ciImage) ?? []

        for feature in features {
            guard
                let qrFeature = feature as? CIQRCodeFeature,
                let message = qrFeature.messageString,
                !message.isEmpty
            else { continue }

            didDetect = true

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let delegateRef = self.delegate
                self.stopSession()
                self.dismiss(self)
                delegateRef?.didScanQRCode(string: message)
            }
            break
        }
    }
}
