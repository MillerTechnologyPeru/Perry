import CPerryGeometry
import PerryObjCInterop

// Auto Layout's visual format language: "H:|-[button(>=80@750)]-8-[label]-|"
// as constraints. A format is an orientation (H, the default, or V), then
// views in brackets, each with its size predicates in parentheses, joined
// by connections ("-" is the standard space, "-n-" or "-(predicates)-" a
// given one, nothing none), between optional superview edges ("|").
// Predicates are a relation (==, <=, >=), a number, metric or view name,
// and an optional priority after "@". The alignment options add equal
// constraints on that attribute between neighbouring views.

enum VisualFormat {
    // NSLayoutAttribute and NSLayoutRelation, as UIKit numbers them.
    static let left = 1, right = 2, top = 3, bottom = 4, leading = 5, trailing = 6, width = 7, height = 8
    static let lessThanOrEqual = -1, equal = 0, greaterThanOrEqual = 1

    /// The standard space between neighbouring views; between a view and
    /// its superview's edge it is the superview's layout margin.
    static let siblingSpace: CGFloat = 8

    /// An edge's margin attribute (leftMargin 13 … trailingMargin 18).
    static func margin(_ edge: Int) -> Int { edge + 12 }

    struct Predicate {
        var relation = equal
        /// A constant, or the view of the same orientation's size, scaled.
        var constant: CGFloat = 0
        var view: NSObject?
        var priority: Float = 1000
        /// The standard space at a superview edge: to its margin.
        var margin = false
    }

    enum Element {
        case superview
        case view(NSObject, [Predicate])
        case connection([Predicate])
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func constraints(format: String, options: UInt, metrics: NSDictionary?, views: NSDictionary?) throws -> [NSLayoutConstraint] {
        var parser = Parser(text: Array(format.filter { !$0.isWhitespace }), metrics: metrics, views: views)
        let (vertical, elements) = try parser.parse()
        let (startEdge, endEdge, sizeAttribute): (Int, Int, Int)
        if vertical {
            (startEdge, endEdge, sizeAttribute) = (top, bottom, height)
        } else if options & 0x30000 == 0x10000 {
            // NSLayoutFormatDirectionLeftToRight.
            (startEdge, endEdge, sizeAttribute) = (left, right, width)
        } else if options & 0x30000 == 0x20000 {
            // NSLayoutFormatDirectionRightToLeft.
            (startEdge, endEdge, sizeAttribute) = (right, left, width)
        } else {
            (startEdge, endEdge, sizeAttribute) = (leading, trailing, width)
        }

        var result: [NSLayoutConstraint] = []
        func add(_ first: NSObject, _ firstAttribute: Int, _ relation: Int, _ second: NSObject?, _ secondAttribute: Int,
                 multiplier: CGFloat = 1, constant: CGFloat, priority: Float) {
            let constraint = NSLayoutConstraint.constraint(NSLayoutConstraint.objCClass, item: first, attribute: firstAttribute, relatedBy: relation,
                                                           toItem: second, attribute: secondAttribute, multiplier: multiplier, constant: constant)
                .unsafeCast(to: NSLayoutConstraint.self)
            constraint.state.priority = priority
            result.append(constraint)
        }

        var laidOut: [NSObject] = []
        var previous: Element?
        var pending: [Predicate]?
        for element in elements {
            switch element {
            case .connection(let predicates):
                pending = predicates
            case .superview:
                // The last view's end to the superview's end.
                if case .view(let view, _) = previous {
                    let superview = try container(of: view)
                    for predicate in pending ?? [Predicate(constant: 0)] {
                        add(superview, predicate.margin ? margin(endEdge) : endEdge, predicate.relation, view, endEdge,
                            constant: predicate.constant, priority: predicate.priority)
                    }
                }
                pending = nil
                previous = element
            case .view(let view, let predicates):
                switch previous {
                case .superview:
                    let superview = try container(of: view)
                    if let pending {
                        for predicate in pending {
                            add(view, startEdge, predicate.relation, superview, predicate.margin ? margin(startEdge) : startEdge,
                                constant: predicate.constant, priority: predicate.priority)
                        }
                    } else {
                        add(view, startEdge, equal, superview, startEdge, constant: 0, priority: 1000)
                    }
                case .view(let before, _):
                    for predicate in pending ?? [Predicate(constant: 0)] {
                        add(view, startEdge, predicate.relation, before, endEdge, constant: predicate.constant, priority: predicate.priority)
                    }
                default:
                    break
                }
                for predicate in predicates {
                    if let other = predicate.view {
                        add(view, sizeAttribute, predicate.relation, other, sizeAttribute, constant: 0, priority: predicate.priority)
                    } else {
                        add(view, sizeAttribute, predicate.relation, nil, 0, constant: predicate.constant, priority: predicate.priority)
                    }
                }
                pending = nil
                laidOut.append(view)
                previous = element
            }
        }

        // NSLayoutFormatAlignAll…: the bit of each attribute to align.
        let attributes = [left, right, top, bottom, leading, trailing, 9, 10, 11, 12]
        for attribute in attributes where options & (1 << UInt(attribute)) != 0 {
            for index in laidOut.indices.dropFirst() {
                add(laidOut[index - 1], attribute, equal, laidOut[index], attribute, constant: 0, priority: 1000)
            }
        }
        return result
    }

    /// The superview "|" stands for: the view's.
    private static func container(of view: NSObject) throws -> NSObject {
        guard let superview = view.as(UIView.self)?.state.superview else {
            throw Failure(description: "a view at the superview's edge has no superview")
        }
        return NSObject(superview)
    }

    struct Parser {
        let text: [Character]
        let metrics: NSDictionary?
        let views: NSDictionary?
        var position = 0

        init(text: [Character], metrics: NSDictionary?, views: NSDictionary?) {
            (self.text, self.metrics, self.views) = (text, metrics, views)
        }

        var current: Character? { position < text.count ? text[position] : nil }

        mutating func take(_ character: Character) -> Bool {
            guard current == character else { return false }
            position += 1
            return true
        }

        mutating func expect(_ character: Character) throws {
            guard take(character) else { throw failure("expected '\(character)'") }
        }

        func failure(_ message: String) -> Failure {
            Failure(description: "\(message) at \(position) in \"\(String(text))\"")
        }

        mutating func parse() throws -> (vertical: Bool, elements: [Element]) {
            var vertical = false
            if text.count >= 2, text[1] == ":", text[0] == "H" || text[0] == "V" {
                vertical = text[0] == "V"
                position = 2
            }
            var elements: [Element] = []
            if take("|") { elements.append(.superview) }
            while let character = current {
                switch character {
                case "-":
                    position += 1
                    if take("|") {
                        // "-|": the standard space to the superview's edge.
                        elements.append(.connection([Predicate(margin: true)]))
                        elements.append(.superview)
                    } else if current == "[" {
                        let atSuperview = elements.last.map { if case .superview = $0 { return true } else { return false } } ?? false
                        elements.append(.connection([atSuperview ? Predicate(margin: true) : Predicate(constant: siblingSpace)]))
                    } else {
                        let predicates = try predicateList()
                        try expect("-")
                        elements.append(.connection(predicates))
                    }
                case "[":
                    position += 1
                    let name = identifier()
                    guard let view = views?.object(forKey: name) else { throw failure("no view named '\(name)'") }
                    var predicates: [Predicate] = []
                    if current == "(" { predicates = try predicateList() }
                    try expect("]")
                    elements.append(.view(view, predicates))
                case "|":
                    position += 1
                    elements.append(.superview)
                default:
                    throw failure("unexpected '\(character)'")
                }
            }
            return (vertical, elements)
        }

        mutating func identifier() -> String {
            let start = position
            while let character = current, character.isLetter || character.isNumber || character == "_" { position += 1 }
            return String(text[start..<position])
        }

        /// A number, or a metric's value.
        mutating func value() throws -> CGFloat {
            let start = position
            if current == "-" || current == "+" { position += 1 }
            while let character = current, character.isNumber || character == "." { position += 1 }
            if position > start, let number = Double(String(text[start..<position])) { return CGFloat(number) }
            position = start
            let name = identifier()
            guard !name.isEmpty, let metric = metrics?.object(forKey: name)?.as(NSNumber.self) else {
                throw failure("no metric named '\(name)'")
            }
            return CGFloat(metric.doubleValue())
        }

        /// A single predicate, or several in parentheses.
        mutating func predicateList() throws -> [Predicate] {
            guard take("(") else { return [try predicate()] }
            var predicates = [try predicate()]
            while take(",") { predicates.append(try predicate()) }
            try expect(")")
            return predicates
        }

        mutating func predicate() throws -> Predicate {
            var predicate = Predicate()
            if take("=") { try expect("=") } else if take("<") { try expect("="); predicate.relation = lessThanOrEqual } else if take(">") {
                try expect("=")
                predicate.relation = greaterThanOrEqual
            }
            let start = position
            let name = identifier()
            if !name.isEmpty, !(name.first?.isNumber ?? false), let view = views?.object(forKey: name) {
                predicate.view = view
            } else {
                position = start
                predicate.constant = try value()
            }
            if take("@") { predicate.priority = Float(try value()) }
            return predicate
        }
    }
}
