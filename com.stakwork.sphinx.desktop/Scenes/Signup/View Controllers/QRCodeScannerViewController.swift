//
//  QRCodeScannerViewController.swift
//  Sphinx
//
//  Created for seed import QR code scanning.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa
import AVFoundation

@MainActor
protocol QRCodeScannerDelegate: AnyObject {
    func didScanQRCode(string: String)
}

@available(macOS 13.0, *)
class QRCodeScannerViewController: NSViewController {

    weak var delegate: QRCodeScannerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

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
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            showNoCameraAlert()
            return
        }

        let session = AVCaptureSession()

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

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showNoCameraAlert()
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        
        guard metadataOutput.availableMetadataObjectTypes.contains(.qr) else {
            showNoCameraAlert()
            return
        }
        metadataOutput.metadataObjectTypes = [.qr]

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

    // MARK: - Internal handler (called on main actor after QR scan)

    func handleScannedString(_ string: String) {
        stopSession()
        let delegateRef = self.delegate
        self.dismiss(self)
        delegateRef?.didScanQRCode(string: string)
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

@available(macOS 13.0, *)
extension QRCodeScannerViewController: @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            metadataObject.type == .qr,
            let scannedString = metadataObject.stringValue
        else { return }

        // Delegate queue is DispatchQueue.main, so we are already on main actor here.
        handleScannedString(scannedString)
    }
}
