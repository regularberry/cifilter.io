//
//  FilterWorkshopViewController.swift
//  CIFilter.io
//
//  Created by Noah Gilmore on 12/8/18.
//  Copyright © 2018 Noah Gilmore. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import Combine
import MobileCoreServices

final class FilterWorkshopViewController: UIViewController {
    private let bag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    private let applicator = AsyncFilterApplicator()
    private let exporter = FilterApplicationExporter()
    private lazy var workshopView: FilterWorkshopView = {
        return FilterWorkshopView(applicator: self.applicator)
    }()
    private var currentImage: RenderingResult? = nil
    private let filter: FilterInfo
    private var shareItem: UIBarButtonItem! = nil
    private var exportItem: UIBarButtonItem! = nil
    private var inputImageCurrentlySelecting: String? = nil
    private var currentGeneratedImageParmaeters: [String: Any]? = nil

    init(filter: FilterInfo) {
        self.filter = filter
        super.init(nibName: nil, bundle: nil)
        self.title = filter.name

        self.shareItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(didTapShareButton))
        self.shareItem.isEnabled = false
        self.exportItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(didTapExportButton))
        self.exportItem.isEnabled = false

        #if DEBUG
            self.navigationItem.rightBarButtonItems = [exportItem, shareItem]
        #else
            self.navigationItem.rightBarButtonItem = shareItem
        #endif

        applicator.events.observeOn(MainScheduler.instance).subscribe(onNext: { event in
            guard case let .generationCompleted(image, _, parameters) = event else {
                self.shareItem.isEnabled = false
                self.exportItem.isEnabled = false
                return
            }
            self.shareItem.isEnabled = true
            self.exportItem.isEnabled = true
            self.currentImage = image
            self.currentGeneratedImageParmaeters = parameters
        }).disposed(by: bag)

        workshopView.didChooseAddImage.sink(receiveValue: { (paramName, view) in
            AnalyticsManager.shared.track(event: "tap_choose_image", properties: ["name": self.filter.name, "parameter_name": paramName])
            self.inputImageCurrentlySelecting = paramName
            #if targetEnvironment(macCatalyst)
            self.presentDocumentBrowserController()
            #else
            self.presentImagePickerController(fromSourceRect: view)
            #endif
        }).store(in: &self.cancellables)
    }

    private func presentImagePickerController(fromSourceRect sourceRect: CGRect) {
        let vc = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        vc.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { [weak self] _ in
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = [kUTTypeImage as String]
            picker.delegate = self
            self?.present(picker, animated: true, completion: nil)
        }))
        vc.addAction(UIAlertAction(title: "Select from library", style: .default, handler: { [weak self] _ in
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = [kUTTypeImage as String]
            picker.delegate = self
            self?.present(picker, animated: true, completion: nil)
        }))
        vc.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
        vc.popoverPresentationController?.sourceView = self.view
        // We extracted the frame from the global coordinate space in SwiftUI, so now we have to
        // convert it back
        vc.popoverPresentationController?.sourceRect = self.view.convert(sourceRect, from: self.view.window!)
        self.present(vc, animated: true, completion: nil)
    }

    private func presentDocumentBrowserController() {
        let vc = UIDocumentPickerViewController(documentTypes: ["public.image"], in: .open)
        vc.delegate = self
        self.present(vc, animated: true, completion: nil)
    }

    @objc private func didTapShareButton() {
        guard let image = currentImage else { return }
        let shareController = UIActivityViewController(activityItems: [image.image], applicationActivities: nil)
        shareController.modalPresentationStyle = .popover
        shareController.popoverPresentationController?.barButtonItem = self.shareItem
        self.present(shareController, animated: true)
    }

    @objc private func didTapExportButton() {
        guard let outputImage = self.currentImage, let parameters = self.currentGeneratedImageParmaeters else {
            return
        }
        exporter.export(outputImage: outputImage, parameters: parameters, filterName: self.filter.name)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = workshopView
        workshopView.set(filter: self.filter)
        AnalyticsManager.shared.track(event: "filter_workshop", properties: ["name": self.filter.name])
    }
}

extension FilterWorkshopViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // TODO: Errors for these
        guard let currentlySelectingParamName = self.inputImageCurrentlySelecting else {
            NonFatalManager.shared.log("NoCurrentlySelectedImageParamFromImagePicker")
            return
        }
        guard let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            NonFatalManager.shared.log("NoOriginalImageFromImagePicker", data: ["param_name": currentlySelectingParamName])
            return
        }
        guard let normalizedImage = originalImage.normalizedRotationImage() else {
            NonFatalManager.shared.log("CouldNotCreateNormalizedImageFromImagePicker", data: ["param_name": currentlySelectingParamName])
            return
        }
        self.workshopView.setImage(normalizedImage, forParameterNamed: currentlySelectingParamName)
        self.dismiss(animated: true, completion: nil)

    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
}

extension FilterWorkshopViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let currentlySelectingParamName = self.inputImageCurrentlySelecting else {
            NonFatalManager.shared.log("NoCurrentlySelectedImageParamFromImagePicker")
            return
        }
        guard let first = urls.first else {
            return
        }
        guard let image = UIImage(contentsOfFile: first.path) else {
            return
        }
        self.workshopView.setImage(image, forParameterNamed: currentlySelectingParamName)
        AnalyticsManager.shared.track(event: "chose_image", properties: ["name": self.filter.name, "parameter_name": currentlySelectingParamName])
    }
}
