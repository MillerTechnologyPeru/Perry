import CPerryGeometry
import PerryObjCInterop

// Auto Layout's visual format language, which
// +constraintsWithVisualFormat:options:metrics:views: reads:
//
//   (H|V:)? (|connection)? [view(predicates)] (connection [view])* (connection|)?
//
// A connection is "-" (the standard spacing), "-n-", "-(predicates)-" or
// nothing (views flush). Predicates are comma-separated, each an optional
// relation (==, <=, >=), a number, metric name or view name, and an
// optional @priority. The options' alignment bits (1 << attribute) align
// every view in the format by that attribute.

enum VisualFormat {
    /// The standard spacing between siblings, and to the superview's edge.
    static let siblingSpacing: CGFloat = 8
    static let edgeSpacing: CGFloat = 20

    struct Predicate {
        var relation = 0
        var constant: CGFloat = 0
        var view: String?
        var priority: Float = 1000
    }

    enum Element {
        case superview
        case view(name: String, predicates: [Predicate])
        /// The space before the next element: nil for none (flush).
        case connection([Predicate])
    }

    struct Failure: Error { let message: String }

    static func parse(_ format: String, metrics: (String) -> CGFloat?) throws -> (vertical: Bool, elements: [Element]) {
        var text = Substring(format.filter { !$0.isWhitespace })
        var vertical = false
        if text.hasPrefix("V:") { vertical = true; text = text.dropFirst(2) } else if text.hasPrefix("H:") { text = text.dropFirst(2) }
        var elements: [Element] = []

        func number(_ token: Substring) throws -> CGFloat {
            if let value = Double(token) { return CGFloat(value) }
            if let value = metrics(String(token)) { return value }
            throw Failure(message: "unknown metric \(token)")
        }

        func predicates(_ list: Substring) throws -> [Predicate] {
            try list.split(separator: ",").map { item in
                var item = item
                var predicate = Predicate()
                if item.hasPrefix("==") { item = item.dropFirst(2) }
                else if item.hasPrefix("<=") { predicate.relation = -1; item = item.dropFirst(2) }
                else if item.hasPrefix(">=") { predicate.relation = 1; item = item.dropFirst(2) }
                if let at = item.firstIndex(of: "@") {
                    predicate.priority = Float(try number(item[item.index(after: at)...]))
                    item = item[..<at]
                }
                if let first = item.first, first.isLetter || first == "_" {
                    if let value = metrics(String(item)) { predicate.constant = value } else { predicate.view = String(item) }
                } else {
                    predicate.constant = try number(item)
                }
                return predicate
            }
        }

        /// Characters up to the matching close.
        func take(until close: Character) throws -> Substring {
            guard let end = text.firstIndex(of: close) else { throw Failure(message: "missing \(close) in \(format)") }
            let inside = text[..<end]
            text = text[text.index(after: end)...]
            return inside
        }

        while let character = text.first {
            switch character {
            case "|":
                text = text.dropFirst()
                elements.append(.superview)
            case "[":
                text = text.dropFirst()
                let inside = try take(until: "]")
                if let open = inside.firstIndex(of: "("), inside.last == ")" {
                    let name = String(inside[..<open])
                    let list = inside[inside.index(after: open)..<inside.index(before: inside.endIndex)]
                    elements.append(.view(name: name, predicates: try predicates(list)))
                } else {
                    elements.append(.view(name: String(inside), predicates: []))
                }
            case "-":
                text = text.dropFirst()
                // "-" alone, "-n-" or "-(…)-".
                if text.first == "(" {
                    text = text.dropFirst()
                    let list = try take(until: ")")
                    guard text.first == "-" else { throw Failure(message: "expected - after (\(list)) in \(format)") }
                    text = text.dropFirst()
                    elements.append(.connection(try predicates(list)))
                } else if let end = text.firstIndex(of: "-"), !text[..<end].contains("["), !text[..<end].contains("|"),
                          !text[..<end].isEmpty {
                    let list = text[..<end]
                    text = text[text.index(after: end)...]
                    elements.append(.connection(try predicates(list)))
                } else {
                    // The standard spacing: an empty list stands for it.
                    elements.append(.connection([]))
                }
            default:
                throw Failure(message: "unexpected \(character) in \(format)")
            }
        }
        return (vertical, elements)
    }

    static func constraints(_ format: String, options: UInt, metrics: NSObject?, views: NSObject?) -> [NSLayoutConstraint] {
        let viewTable = views?.as(NSDictionary.self)
        let metricTable = metrics?.as(NSDictionary.self)
        func metric(_ name: String) -> CGFloat? {
            guard let value = metricTable?.object(forKey: name) else { return nil }
            return CGFloat(NSNumber(value.objcObject).doubleValue())
        }
        func view(_ name: String) -> NSObject? { viewTable?.object(forKey: name) }

        let parsed: (vertical: Bool, elements: [Element])
        do {
            parsed = try parse(format, metrics: metric)
        } catch let failure as Failure {
            appKitWarning("layout: \(failure.message)")
            return []
        } catch {
            return []
        }
        let leading = parsed.vertical ? 3 : 5, trailing = parsed.vertical ? 4 : 6, size = parsed.vertical ? 8 : 7
        var made: [NSLayoutConstraint] = []
        func add(_ item: NSObject?, _ attribute: Int, _ relation: Int, _ other: NSObject?, _ otherAttribute: Int, _ constant: CGFloat,
                 _ priority: Float) {
            let constraint = NSLayoutConstraint(item: item, attribute: attribute, relation: relation, to: other, attribute: otherAttribute,
                                                multiplier: 1, constant: constant)
            constraint.priority = priority
            made.append(constraint)
        }

        var named: [NSObject] = []
        for element in parsed.elements {
            if case .view(let name, _) = element, let found = view(name) { named.append(found) }
        }
        let superview = named.first.flatMap { $0.as(NSView.self)?.superview }

        /// The item before: a view, or the superview's leading edge; and the
        /// connection since it: nil for none (flush), empty for the
        /// standard spacing.
        var previous: (item: NSObject?, isSuperview: Bool)?
        var spacing: [Predicate]?
        func gap(standard: CGFloat) -> [Predicate] {
            guard let spacing else { return [Predicate()] }
            return spacing.isEmpty ? [Predicate(constant: standard)] : spacing
        }
        for element in parsed.elements {
            switch element {
            case .superview:
                if let previous, let item = previous.item, !previous.isSuperview {
                    // [view]-n-| : superview.trailing (relation) view.trailing + n.
                    for predicate in gap(standard: edgeSpacing) {
                        add(superview, trailing, predicate.relation, item, trailing, predicate.constant, predicate.priority)
                    }
                }
                previous = (superview, true)
                spacing = nil
            case .connection(let list):
                spacing = list
            case .view(let name, let predicates):
                guard let item = view(name) else {
                    appKitWarning("layout: no view \(name) for \(format)")
                    continue
                }
                if let previous {
                    let isEdge = previous.isSuperview
                    for predicate in gap(standard: isEdge ? edgeSpacing : siblingSpacing) {
                        add(item, leading, predicate.relation, previous.item, isEdge ? leading : trailing, predicate.constant,
                            predicate.priority)
                    }
                }
                for predicate in predicates {
                    if let other = predicate.view {
                        add(item, size, predicate.relation, view(other), size, 0, predicate.priority)
                    } else {
                        add(item, size, predicate.relation, nil, 0, predicate.constant, predicate.priority)
                    }
                }
                previous = (item, false)
                spacing = nil
            }
        }

        // Alignment options: each bit 1 << attribute.
        if named.count > 1 {
            for attribute in 1...12 where options & (1 << UInt(attribute)) != 0 {
                for other in named.dropFirst() { add(other, attribute, 0, named[0], attribute, 0, 1000) }
            }
        }
        return made
    }
}
