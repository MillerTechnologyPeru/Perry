import GraphiteBase

// The Script Manager's answers for one Roman script, English and the
// United States: Graphite's ScriptManager.

/// long GetScriptVariable(short script, short selector).
@c(_GetScriptVariable)
public func GetScriptVariable(_ script: Int16, _ selector: Int16) -> Int {
    ScriptManager.scriptVariable(script: script, selector: ScriptVariable(rawValue: selector))
}

/// long GetScriptManagerVariable(short selector).
@c(_GetScriptManagerVariable)
public func GetScriptManagerVariable(_ selector: Int16) -> Int {
    ScriptManager.managerVariable(ScriptManagerVariable(rawValue: selector))
}

/// ScriptCode IntlScript(void).
@c(_IntlScript)
public func IntlScript() -> Int16 {
    ScriptManager.systemScript
}
