import SwiftUI
import UIKit

/// A full-window ruler; its center marks geometry, not a detected fold or panel boundary.
final class DisplayGridController: UIViewController {
    private let grid = DisplayGridView()
    private let summary = UILabel()

    override func loadView() {
        view = grid
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let done = UIButton(type: .system)
        done.configuration = .borderedProminent()
        done.setTitle("Done", for: .normal)
        done.addTarget(self, action: #selector(close), for: .touchUpInside)
        summary.numberOfLines = 0
        summary.font = .preferredFont(forTextStyle: .body)
        summary.adjustsFontForContentSizeCategory = true
        summary.backgroundColor = .systemBackground
        let controls = UIStackView(arrangedSubviews: [done, summary])
        controls.axis = .vertical
        controls.alignment = .leading
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            controls.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        view.accessibilityViewIsModal = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: summary)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        summary.text = "Canvas: \(DisplayReading.dimensions(view.bounds.size)) pt\n100-point grid. Center line: x = \(DisplayReading.number(view.bounds.midX)) pt. This is the geometric midpoint, not a detected hinge."
        grid.setNeedsDisplay()
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

#if DEBUG
    #Preview { DisplayGridController() }
#endif
