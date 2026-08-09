import PatchlightCore
import SwiftUI
import UIKit

@_spi(Testing)
public enum DiffRendererMode: Equatable, Sendable {
    case unified
    case split
}

/// A viewport-lazy native diff surface. UICollectionView owns virtualization;
/// reusable TextKit-backed cells never instantiate one SwiftUI view per line.
struct PatchlightDiffCollectionView: UIViewRepresentable {
    let file: DiffFile
    let headOID: GitObjectID
    let mode: DiffRendererMode
    let threads: [ReviewThread]
    let onSelectAnchor: (DiffAnchor) -> Void
    let onReachedEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectAnchor: onSelectAnchor, onReachedEnd: onReachedEnd)
    }

    func makeUIView(context: Context) -> UICollectionView {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration),
        )
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            DiffUnifiedCell.self,
            forCellWithReuseIdentifier: DiffUnifiedCell.reuseIdentifier,
        )
        collectionView.register(
            DiffSplitCell.self,
            forCellWithReuseIdentifier: DiffSplitCell.reuseIdentifier,
        )
        collectionView.register(
            DiffHunkCell.self,
            forCellWithReuseIdentifier: DiffHunkCell.reuseIdentifier,
        )
        collectionView.register(
            DiffThreadCell.self,
            forCellWithReuseIdentifier: DiffThreadCell.reuseIdentifier,
        )
        context.coordinator.update(
            file: file,
            headOID: headOID,
            mode: mode,
            threads: threads,
            collectionView: collectionView,
        )
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.onSelectAnchor = onSelectAnchor
        context.coordinator.onReachedEnd = onReachedEnd
        context.coordinator.update(
            file: file,
            headOID: headOID,
            mode: mode,
            threads: threads,
            collectionView: collectionView,
        )
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        private var rows: [DiffRenderedRow] = []
        private var identity: Identity?
        private var file: DiffFile?
        private var headOID: GitObjectID?
        private var didReachEnd = false
        var onSelectAnchor: (DiffAnchor) -> Void
        var onReachedEnd: () -> Void
        fileprivate private(set) var configuredCellCount = 0
        fileprivate var rowCount: Int {
            rows.count
        }

        init(
            onSelectAnchor: @escaping (DiffAnchor) -> Void,
            onReachedEnd: @escaping () -> Void,
        ) {
            self.onSelectAnchor = onSelectAnchor
            self.onReachedEnd = onReachedEnd
        }

        func update(
            file: DiffFile,
            headOID: GitObjectID,
            mode: DiffRendererMode,
            threads: [ReviewThread],
            collectionView: UICollectionView,
        ) {
            let identity = Identity(file: file, headOID: headOID, mode: mode, threads: threads)
            guard self.identity != identity else { return }
            self.identity = identity
            self.file = file
            self.headOID = headOID
            didReachEnd = false
            rows = DiffRowBuilder.rows(file: file, mode: mode, threads: threads)
            collectionView.reloadData()
        }

        func numberOfSections(in _: UICollectionView) -> Int {
            1
        }

        func collectionView(
            _: UICollectionView,
            numberOfItemsInSection _: Int,
        ) -> Int {
            rows.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath,
        ) -> UICollectionViewCell {
            configuredCellCount += 1
            switch rows[indexPath.item] {
                case let .hunk(header):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: DiffHunkCell.reuseIdentifier,
                        for: indexPath,
                    ) as! DiffHunkCell
                    cell.configure(header: header)
                    return cell
                case let .unified(line):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: DiffUnifiedCell.reuseIdentifier,
                        for: indexPath,
                    ) as! DiffUnifiedCell
                    cell.configure(line: line)
                    return cell
                case let .split(base, head):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: DiffSplitCell.reuseIdentifier,
                        for: indexPath,
                    ) as! DiffSplitCell
                    cell.configure(base: base, head: head)
                    return cell
                case let .thread(thread):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: DiffThreadCell.reuseIdentifier,
                        for: indexPath,
                    ) as! DiffThreadCell
                    cell.configure(thread: thread)
                    return cell
            }
        }

        func collectionView(
            _: UICollectionView,
            didSelectItemAt indexPath: IndexPath,
        ) {
            guard let file, let headOID else { return }
            let line: DiffLine? = switch rows[indexPath.item] {
                case let .unified(value): value
                case let .split(base, head): head ?? base
                case .hunk, .thread: nil
            }
            guard let line,
                  let hunk = file.hunks
                  .first(where: { $0.lines.contains(where: { $0.id == line.id }) }),
                  let lineIndex = hunk.lines.firstIndex(where: { $0.id == line.id })
            else { return }
            let side: DiffSide = line.kind == .deletion ? .base : .head
            onSelectAnchor(DiffAnchor(
                path: file.path,
                side: side,
                commitOID: headOID,
                blobOID: side == .base ? file.baseBlobOID : file.headBlobOID,
                line: side == .base ? line.oldLine : line.newLine,
                startLine: nil,
                contextFingerprint: DraftAnchorMapper.fingerprint(
                    lineIndex: lineIndex,
                    in: hunk.lines,
                ),
            ))
        }

        func collectionView(
            _: UICollectionView,
            willDisplay _: UICollectionViewCell,
            forItemAt indexPath: IndexPath,
        ) {
            guard !didReachEnd, indexPath.item == rows.count - 1 else { return }
            didReachEnd = true
            onReachedEnd()
        }

        private struct Identity: Equatable {
            let file: DiffFile
            let headOID: GitObjectID
            let mode: DiffRendererMode
            let threads: [ReviewThread]
        }
    }
}

#if DEBUG
    @_spi(Testing)
    public struct PatchlightDiffRendererMeasurement: Sendable {
        public let rowCount: Int
        public let configuredCellCount: Int

        public init(rowCount: Int, configuredCellCount: Int) {
            self.rowCount = rowCount
            self.configuredCellCount = configuredCellCount
        }
    }

    @_spi(Testing)
    @MainActor
    public enum PatchlightDiffRendererTesting {
        public static func measureInitialViewport(
            file: DiffFile,
            mode: DiffRendererMode,
            viewport: CGSize,
        ) -> PatchlightDiffRendererMeasurement {
            let coordinator = PatchlightDiffCollectionView.Coordinator(
                onSelectAnchor: { _ in },
                onReachedEnd: {},
            )
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            let collectionView = UICollectionView(
                frame: CGRect(origin: .zero, size: viewport),
                collectionViewLayout: UICollectionViewCompositionalLayout
                    .list(using: configuration),
            )
            collectionView.register(
                DiffUnifiedCell.self,
                forCellWithReuseIdentifier: DiffUnifiedCell.reuseIdentifier,
            )
            collectionView.register(
                DiffSplitCell.self,
                forCellWithReuseIdentifier: DiffSplitCell.reuseIdentifier,
            )
            collectionView.register(
                DiffHunkCell.self,
                forCellWithReuseIdentifier: DiffHunkCell.reuseIdentifier,
            )
            collectionView.register(
                DiffThreadCell.self,
                forCellWithReuseIdentifier: DiffThreadCell.reuseIdentifier,
            )
            collectionView.dataSource = coordinator
            coordinator.update(
                file: file,
                headOID: GitObjectID(rawValue: String(repeating: "0", count: 40)),
                mode: mode,
                threads: [],
                collectionView: collectionView,
            )
            collectionView.layoutIfNeeded()
            return PatchlightDiffRendererMeasurement(
                rowCount: coordinator.rowCount,
                configuredCellCount: coordinator.configuredCellCount,
            )
        }
    }
#endif

private enum DiffRenderedRow {
    case hunk(String)
    case unified(DiffLine)
    case split(base: DiffLine?, head: DiffLine?)
    case thread(ReviewThread)
}

private enum DiffRowBuilder {
    static func rows(
        file: DiffFile,
        mode: DiffRendererMode,
        threads: [ReviewThread],
    ) -> [DiffRenderedRow] {
        var result: [DiffRenderedRow] = []
        for hunk in file.hunks {
            result.append(.hunk(hunk.header))
            switch mode {
                case .unified:
                    for line in hunk.lines {
                        result.append(.unified(line))
                        result.append(contentsOf: matchingThreads(line: line, in: threads).map {
                            .thread($0)
                        })
                    }
                case .split:
                    for row in splitRows(hunk.lines) {
                        result.append(row)
                        guard case let .split(base, head) = row else { continue }
                        let matches: [ReviewThread] = [base, head].compactMap(\.self).flatMap {
                            matchingThreads(line: $0, in: threads)
                        }
                        let unique = matches.reduce(into: [ReviewThread]()) { values, thread in
                            if !values.contains(where: { $0.id == thread.id }) {
                                values.append(thread)
                            }
                        }
                        result.append(contentsOf: unique.map { .thread($0) })
                    }
            }
        }
        return result
    }

    private static func matchingThreads(
        line: DiffLine,
        in threads: [ReviewThread],
    ) -> [ReviewThread] {
        threads.filter { thread in
            switch thread.side {
                case .base: thread.line == line.oldLine
                case .head, .none: thread.line == line.newLine
            }
        }
    }

    private static func splitRows(_ lines: [DiffLine]) -> [DiffRenderedRow] {
        var rows: [DiffRenderedRow] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.kind == .context || line.kind == .metadata {
                rows.append(.split(base: line, head: line))
                index += 1
                continue
            }

            var deletions: [DiffLine] = []
            var additions: [DiffLine] = []
            while index < lines.count, lines[index].kind == .deletion {
                deletions.append(lines[index])
                index += 1
            }
            while index < lines.count, lines[index].kind == .addition {
                additions.append(lines[index])
                index += 1
            }
            if deletions.isEmpty, additions.isEmpty {
                rows.append(.split(
                    base: line.kind == .deletion ? line : nil,
                    head: line.kind == .addition ? line : nil,
                ))
                index += 1
                continue
            }
            for pairIndex in 0 ..< max(deletions.count, additions.count) {
                rows.append(.split(
                    base: pairIndex < deletions.count ? deletions[pairIndex] : nil,
                    head: pairIndex < additions.count ? additions[pairIndex] : nil,
                ))
            }
        }
        return rows
    }
}

private final class DiffThreadCell: UICollectionViewCell {
    static let reuseIdentifier = "DiffThreadCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .callout)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
        contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(thread: ReviewThread) {
        let first = thread.comments.first
        label.text = [first?.authorLogin, first?.bodyMarkdown]
            .compactMap(\.self)
            .joined(separator: ": ")
        accessibilityLabel = label.text
    }
}

private final class DiffHunkCell: UICollectionViewCell {
    static let reuseIdentifier = "DiffHunkCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
        contentView.backgroundColor = .tertiarySystemFill
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(header: String) {
        label.text = header
        accessibilityLabel = header
    }
}

private final class DiffUnifiedCell: UICollectionViewCell {
    static let reuseIdentifier = "DiffUnifiedCell"
    private let panel = DiffLinePanel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            panel.topAnchor.constraint(equalTo: contentView.topAnchor),
            panel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(line: DiffLine) {
        panel.configure(line: line, showsBothNumbers: true)
        accessibilityLabel = panel.accessibilityDescription
    }
}

private final class DiffSplitCell: UICollectionViewCell {
    static let reuseIdentifier = "DiffSplitCell"
    private let base = DiffLinePanel()
    private let head = DiffLinePanel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [base, head])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        stack.backgroundColor = .separator
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(base baseLine: DiffLine?, head headLine: DiffLine?) {
        base.configure(line: baseLine, showsBothNumbers: false)
        head.configure(line: headLine, showsBothNumbers: false)
        accessibilityLabel = [base.accessibilityDescription, head.accessibilityDescription]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

/// UITextView is the TextKit-backed, selectable code surface inside each
/// reusable collection cell.
private final class DiffLinePanel: UIView {
    private let oldNumber = UILabel()
    private let newNumber = UILabel()
    private let textView = UITextView()
    private(set) var accessibilityDescription = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        for item in [oldNumber, newNumber] {
            item.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            item.textColor = .tertiaryLabel
            item.textAlignment = .right
            item.setContentHuggingPriority(.required, for: .horizontal)
            item.widthAnchor.constraint(equalToConstant: 36).isActive = true
        }
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [oldNumber, newNumber, textView])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(line: DiffLine?, showsBothNumbers: Bool) {
        guard let line else {
            oldNumber.text = nil
            newNumber.text = nil
            textView.text = nil
            backgroundColor = .secondarySystemBackground
            accessibilityDescription = ""
            return
        }
        oldNumber.isHidden = !showsBothNumbers && line.oldLine == nil
        newNumber.isHidden = !showsBothNumbers && line.newLine == nil
        oldNumber.text = line.oldLine.map(String.init)
        newNumber.text = line.newLine.map(String.init)
        textView.text = line.text.isEmpty ? " " : line.text
        backgroundColor = switch line.kind {
            case .addition: UIColor.systemGreen.withAlphaComponent(0.12)
            case .deletion: UIColor.systemRed.withAlphaComponent(0.12)
            case .context, .metadata: UIColor.systemBackground
        }
        let number = line.newLine ?? line.oldLine
        let kind = switch line.kind {
            case .addition: String(localized: .addition)
            case .deletion: String(localized: .deletion)
            case .context: String(localized: .contextLine)
            case .metadata: String(localized: .diffMetadata)
        }
        accessibilityDescription = "\(kind) \(number.map(String.init) ?? ""): \(line.text)"
    }
}
