// A Cassowary linear constraint solver, in Kiwi's formulation, as Auto
// Layout solves constraints: linear equalities and inequalities, each
// required or weighed by a strength, solved with the simplex method so that
// the required ones hold and the weighted error of the others is least.
// UIKit and AppKit lay out their views with it.

/// The solver's scalar: CoreGraphics' CGFloat, double on 64-bit and float
/// on 32-bit.
#if _pointerBitWidth(_32)
public typealias LayoutScalar = Float
#else
public typealias LayoutScalar = Double
#endif

/// A value the solver finds.
public final class LayoutVariable {
    public init() {}
    public var value: LayoutScalar = 0
}

/// A linear expression: a sum of variables with coefficients, plus a constant.
public struct LayoutExpression {
    public var terms: [(variable: LayoutVariable, coefficient: LayoutScalar)] = []
    public var constant: LayoutScalar = 0

    public init(constant: LayoutScalar = 0) { self.constant = constant }
    public init(_ variable: LayoutVariable) { terms = [(variable, 1)] }

    public static func + (a: LayoutExpression, b: LayoutExpression) -> LayoutExpression {
        var sum = a
        sum.terms += b.terms
        sum.constant += b.constant
        return sum
    }

    public static func * (a: LayoutExpression, k: LayoutScalar) -> LayoutExpression {
        var product = a
        product.terms = a.terms.map { ($0.variable, $0.coefficient * k) }
        product.constant *= k
        return product
    }

    public static func - (a: LayoutExpression, b: LayoutExpression) -> LayoutExpression { a + b * -1 }
    public static func + (a: LayoutExpression, k: LayoutScalar) -> LayoutExpression { a + LayoutExpression(constant: k) }
}

/// Simplex rows, and the symbols they are written in.
public final class LayoutSolver {
    public enum Relation { case lessOrEqual, equal, greaterOrEqual }

    /// Strengths: a required constraint must hold; the others are weighed
    /// by priority, each step of priority outweighing the one below.
    public static let required: Double = 1_001_001_000

    /// A constraint priority's strength: required at 1000, else a weight
    /// that grows with it.
    public static func strength(_ priority: Float) -> Double {
        priority >= 1000 ? required : Double(max(priority, 1)) * 1000
    }

    public init() {}

    private enum Kind { case external, slack, error, dummy }

    private struct Symbol: Hashable, Comparable {
        let id: Int
        let kind: Kind
        static func < (a: Symbol, b: Symbol) -> Bool { a.id < b.id }
    }

    private final class Row {
        var cells: [Symbol: Double] = [:]
        var constant: Double

        init(_ constant: Double) { self.constant = constant }
        init(copying row: Row) { cells = row.cells; constant = row.constant }

        func insert(_ symbol: Symbol, _ coefficient: Double = 1) {
            let value = cells[symbol, default: 0] + coefficient
            if abs(value) < 1e-8 { cells[symbol] = nil } else { cells[symbol] = value }
        }

        func insert(_ row: Row, _ coefficient: Double = 1) {
            constant += row.constant * coefficient
            for (symbol, value) in row.cells { insert(symbol, value * coefficient) }
        }

        func reverseSign() {
            constant = -constant
            for symbol in cells.keys { cells[symbol] = -cells[symbol]! }
        }

        /// Solves the row (= 0) for `symbol`.
        func solve(for symbol: Symbol) {
            let coefficient = -1 / cells.removeValue(forKey: symbol)!
            constant *= coefficient
            for key in cells.keys { cells[key]! *= coefficient }
        }

        func solve(for lhs: Symbol, _ rhs: Symbol) {
            insert(lhs, -1)
            solve(for: rhs)
        }

        func coefficient(_ symbol: Symbol) -> Double { cells[symbol] ?? 0 }

        func substitute(_ symbol: Symbol, _ row: Row) {
            if let coefficient = cells.removeValue(forKey: symbol) { insert(row, coefficient) }
        }

        var sortedSymbols: [Symbol] { cells.keys.sorted() }
    }

    private var nextID = 1
    private var symbols: [ObjectIdentifier: (variable: LayoutVariable, symbol: Symbol)] = [:]
    private var rows: [Symbol: Row] = [:]
    private let objective = Row(0)
    private var artificial: Row?

    private func makeSymbol(_ kind: Kind) -> Symbol {
        defer { nextID += 1 }
        return Symbol(id: nextID, kind: kind)
    }

    private func symbol(for variable: LayoutVariable) -> Symbol {
        if let entry = symbols[ObjectIdentifier(variable)] { return entry.symbol }
        let symbol = makeSymbol(.external)
        symbols[ObjectIdentifier(variable)] = (variable, symbol)
        return symbol
    }

    /// Adds `expression relation 0` at `strength`; false when a required
    /// constraint cannot be satisfied with those already added.
    @discardableResult
    public func add(_ expression: LayoutExpression, _ relation: Relation, strength: Double) -> Bool {
        let row = Row(Double(expression.constant))
        for term in expression.terms where abs(term.coefficient) > 1e-8 {
            let symbol = symbol(for: term.variable)
            if let basic = rows[symbol] { row.insert(basic, Double(term.coefficient)) } else { row.insert(symbol, Double(term.coefficient)) }
        }
        var marker: Symbol
        var other: Symbol?
        switch relation {
        case .lessOrEqual, .greaterOrEqual:
            let sign: Double = relation == .lessOrEqual ? 1 : -1
            marker = makeSymbol(.slack)
            row.insert(marker, sign)
            if strength < LayoutSolver.required {
                let error = makeSymbol(.error)
                other = error
                row.insert(error, -sign)
                objective.insert(error, strength)
            }
        case .equal:
            if strength < LayoutSolver.required {
                let plus = makeSymbol(.error), minus = makeSymbol(.error)
                marker = plus
                other = minus
                row.insert(plus, -1)
                row.insert(minus, 1)
                objective.insert(plus, strength)
                objective.insert(minus, strength)
            } else {
                marker = makeSymbol(.dummy)
                row.insert(marker)
            }
        }
        if row.constant < 0 { row.reverseSign() }

        var subject = chooseSubject(row, marker: marker, other: other)
        if subject == nil, row.cells.keys.allSatisfy({ $0.kind == .dummy }) {
            guard abs(row.constant) < 1e-8 else { return false }
            subject = marker
        }
        if let subject {
            row.solve(for: subject)
            substitute(subject, row)
            rows[subject] = row
        } else if !addWithArtificialVariable(row) {
            return false
        }
        return optimize(objective)
    }

    private func chooseSubject(_ row: Row, marker: Symbol, other: Symbol?) -> Symbol? {
        if let external = row.sortedSymbols.first(where: { $0.kind == .external }) { return external }
        if marker.kind == .slack || marker.kind == .error, row.coefficient(marker) < 0 { return marker }
        if let other, other.kind == .slack || other.kind == .error, row.coefficient(other) < 0 { return other }
        return nil
    }

    private func addWithArtificialVariable(_ row: Row) -> Bool {
        let symbol = makeSymbol(.slack)
        rows[symbol] = Row(copying: row)
        artificial = Row(copying: row)
        _ = optimize(artificial!)
        let success = abs(artificial!.constant) < 1e-8
        artificial = nil
        if let basic = rows.removeValue(forKey: symbol) {
            if basic.cells.isEmpty { return success }
            guard let entering = basic.sortedSymbols.first(where: { $0.kind == .slack || $0.kind == .error }) else { return false }
            basic.solve(for: symbol, entering)
            substitute(entering, basic)
            rows[entering] = basic
        }
        for basic in rows.values { basic.cells[symbol] = nil }
        objective.cells[symbol] = nil
        return success
    }

    private func substitute(_ symbol: Symbol, _ row: Row) {
        for basic in rows.values { basic.substitute(symbol, row) }
        objective.substitute(symbol, row)
        artificial?.substitute(symbol, row)
    }

    /// Pivots until the objective cannot be reduced; false if unbounded.
    private func optimize(_ objective: Row) -> Bool {
        for _ in 0..<10_000 {
            guard let entering = objective.sortedSymbols.first(where: { $0.kind != .dummy && objective.cells[$0]! < 0 }) else {
                return true
            }
            var leaving: Symbol?
            var best = Double.greatestFiniteMagnitude
            for symbol in rows.keys.sorted() where symbol.kind != .external {
                let coefficient = rows[symbol]!.coefficient(entering)
                guard coefficient < 0 else { continue }
                let ratio = -rows[symbol]!.constant / coefficient
                if ratio < best { best = ratio; leaving = symbol }
            }
            guard let leaving, let row = rows.removeValue(forKey: leaving) else { return false }
            row.solve(for: leaving, entering)
            substitute(entering, row)
            rows[entering] = row
        }
        return false
    }

    /// Writes the solution into the variables.
    public func updateVariables() {
        for (variable, symbol) in symbols.values { variable.value = LayoutScalar(rows[symbol]?.constant ?? 0) }
    }
}
