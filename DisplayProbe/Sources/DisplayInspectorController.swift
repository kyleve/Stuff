import SwiftUI
import UIKit

/// Captures live measurements while visible and keeps explicitly saved readings for this session.
final class DisplayInspectorController: UITableViewController {
    private struct SavedReading {
        let label: String
        let date: Date
        let reading: DisplayReading

        var report: String {
            "\(label) — \(date.formatted(date: .abbreviated, time: .standard))\n\(reading.report)"
        }
    }

    private var reading: DisplayReading?
    private var saved: [SavedReading] = []
    private var refreshTimer: Timer?

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init()")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Display Probe"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Grid",
            style: .plain,
            target: self,
            action: #selector(showGrid),
        )
        toolbarItems = [
            UIBarButtonItem(
                title: "Save reading",
                style: .plain,
                target: self,
                action: #selector(saveReading),
            ),
            .flexibleSpace(),
            UIBarButtonItem(
                title: "Share",
                style: .plain,
                target: self,
                action: #selector(shareReadings),
            ),
        ]
        tableView.allowsSelection = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshReading()
        refreshTimer?.invalidate()
        // Poll for screen-mode changes as well as layout changes; no background work or
        // persistence.
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(refreshReading),
            userInfo: nil,
            repeats: true,
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshReading()
    }

    @objc private func refreshReading() {
        let latest = view.window.flatMap { DisplayReading.capture(window: $0) }
        guard latest != reading else { return }
        reading = latest
        tableView.reloadData()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        2
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? (reading?.fields.count ?? 1) : max(saved.count, 1)
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Live · current window’s screen" : "Saved readings · this session"
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? "Fold, unfold, or rotate, then compare these values. Native pixels keep UIKit’s native coordinate order. The current scene does not identify inactive panels or a physical hinge."
            : "Save each state with a label, then Share to export the comparison. Readings are cleared when the app closes."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath,
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "measurement")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "measurement")
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            if let field = reading?.fields[indexPath.row] {
                content.text = field.value
                content.secondaryText = field.label
            } else {
                content.text = "Waiting for an attached window"
            }
        } else if saved.isEmpty {
            content.text = "No saved readings"
        } else {
            let snapshot = saved[indexPath.row]
            content.text = snapshot.label
            content.secondaryText = snapshot.report
        }
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }

    @objc private func showGrid() {
        let grid = DisplayGridController()
        grid.modalPresentationStyle = .fullScreen
        present(grid, animated: true)
    }

    @objc private func saveReading() {
        let alert = UIAlertController(
            title: "Save reading",
            message: "Label the current device state, such as folded or unfolded.",
            preferredStyle: .alert,
        )
        alert.addTextField { field in
            field.placeholder = "Device state"
            field.text = "Reading \(self.saved.count + 1)"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let window = view.window,
                  let reading = DisplayReading.capture(window: window) else { return }
            let label = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            saved.append(SavedReading(
                label: label.flatMap { $0.isEmpty ? nil : $0 } ?? "Reading \(saved.count + 1)",
                date: .now,
                reading: reading,
            ))
            tableView.reloadData()
        })
        present(alert, animated: true)
    }

    @objc private func shareReadings() {
        refreshReading()
        guard let reading else { return }
        let report = (["Display Probe\nCurrent reading\n\(reading.report)"] + saved.map(\.report))
            .joined(separator: "\n\n")
        let activity = UIActivityViewController(activityItems: [report], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = toolbarItems?.last
        present(activity, animated: true)
    }
}

#if DEBUG
    #Preview {
        UINavigationController(rootViewController: DisplayInspectorController())
    }
#endif
