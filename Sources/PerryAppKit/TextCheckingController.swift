import CPerryGeometry
import PerryObjCInterop

// NSTextCheckingController: spelling, grammar and substitution checking for
// a text view that isn't an NSTextView, through its NSTextCheckingClient.
// NSSpellChecker finds nothing to correct here (Pickers.swift), so checking
// annotates nothing and there are no panels to show; the controller keeps
// its document tag and its client's text input traits, which apps set and
// read back.

@ObjCClass("NSTextCheckingController")
open class NSTextCheckingController: NSObject {
    /// Not retained: the client owns the controller.
    var clientObject: UnsafeMutableRawPointer?
    var documentTag = 0
    /// NSTextInputTraitType values by trait (autocorrection, spell
    /// checking, smart quotes …): default (0) until set.
    var traits: [String: Int] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithClient:")
    public required init(client: NSObject?) {
        super.init()
        clientObject = client?.objcObject
    }

    @ObjCMethod("client") func controllerClient() -> NSObject? { clientObject.map(NSObject.init) }

    /// The spelling document's tag, made the first time it is asked for.
    @ObjCMethod("spellCheckerDocumentTag")
    func spellCheckerDocumentTag() -> Int {
        if documentTag == 0 { documentTag = NSSpellChecker.uniqueSpellDocumentTag() }
        return documentTag
    }
    @ObjCMethod("setSpellCheckerDocumentTag:") func setSpellCheckerDocumentTag(_ value: Int) { documentTag = value }

    /// Done with the client: its spelling document closes.
    @ObjCMethod("invalidate")
    func invalidate() {
        if documentTag != 0 { NSSpellChecker.sharedSpellChecker().closeSpellDocument(withTag: documentTag) }
        clientObject = nil
    }

    // Changes in the client's text, which would be checked again.
    @ObjCMethod("didChangeTextInRange:") func didChangeText(in range: NSRange) {}
    @ObjCMethod("insertedTextInRange:") func insertedText(in range: NSRange) {}
    @ObjCMethod("didChangeSelectedRange") func didChangeSelectedRange() {}
    @ObjCMethod("didChangeText") func didChangeText() {}
    @ObjCMethod("considerTextCheckingForRange:") func considerTextChecking(for range: NSRange) {}
    @ObjCMethod("checkTextInRange:types:options:") func checkText(in range: NSRange, types: UInt64, options: NSObject?) {}
    @ObjCMethod("updateCandidates") func updateCandidates() {}

    // The Edit menu's spelling and substitution commands: nothing is
    // misspelled, and there are no spelling or substitutions panels.
    @ObjCMethod("checkTextInSelection:") func checkTextInSelection(_ sender: NSObject?) {}
    @ObjCMethod("checkTextInDocument:") func checkTextInDocument(_ sender: NSObject?) {}
    @ObjCMethod("checkSpelling:") func checkSpelling(_ sender: NSObject?) {}
    @ObjCMethod("showGuessPanel:") func showGuessPanel(_ sender: NSObject?) {}
    @ObjCMethod("changeSpelling:") func changeSpelling(_ sender: NSObject?) {}
    @ObjCMethod("ignoreSpelling:") func ignoreSpelling(_ sender: NSObject?) {}
    @ObjCMethod("orderFrontSubstitutionsPanel:") func orderFrontSubstitutionsPanel(_ sender: NSObject?) {}
    @ObjCMethod("validateMenuItem:") func validateMenuItem(_ item: NSObject?) -> Bool { true }
    @ObjCMethod("validateUserInterfaceItem:") func validateUserInterfaceItem(_ item: NSObject?) -> Bool { true }

    /// No annotations are made, so none are valid.
    @ObjCMethod("validAnnotations") func validAnnotations() -> NSObject { NSMutableArray.empty() }

    /// No suggestions for any word: no menu of them.
    @ObjCMethod("menuAtIndex:clickedOnSelection:effectiveRange:")
    func menu(at location: UInt, clickedOnSelection: Bool, effectiveRange: UnsafeMutablePointer<NSRange>?) -> NSObject? { nil }

    @ObjCMethod("isEditable") func isEditable() -> Bool { true }
    @ObjCMethod("isSelectable") func isSelectable() -> Bool { true }

    // MARK: Text input traits

    @ObjCMethod("autocorrectionType") func autocorrectionType() -> Int { traits["autocorrection"] ?? 0 }
    @ObjCMethod("setAutocorrectionType:") func setAutocorrectionType(_ value: Int) { traits["autocorrection"] = value }
    @ObjCMethod("spellCheckingType") func spellCheckingType() -> Int { traits["spellChecking"] ?? 0 }
    @ObjCMethod("setSpellCheckingType:") func setSpellCheckingType(_ value: Int) { traits["spellChecking"] = value }
    @ObjCMethod("grammarCheckingType") func grammarCheckingType() -> Int { traits["grammarChecking"] ?? 0 }
    @ObjCMethod("setGrammarCheckingType:") func setGrammarCheckingType(_ value: Int) { traits["grammarChecking"] = value }
    @ObjCMethod("smartQuotesType") func smartQuotesType() -> Int { traits["smartQuotes"] ?? 0 }
    @ObjCMethod("setSmartQuotesType:") func setSmartQuotesType(_ value: Int) { traits["smartQuotes"] = value }
    @ObjCMethod("smartDashesType") func smartDashesType() -> Int { traits["smartDashes"] ?? 0 }
    @ObjCMethod("setSmartDashesType:") func setSmartDashesType(_ value: Int) { traits["smartDashes"] = value }
    @ObjCMethod("smartInsertDeleteType") func smartInsertDeleteType() -> Int { traits["smartInsertDelete"] ?? 0 }
    @ObjCMethod("setSmartInsertDeleteType:") func setSmartInsertDeleteType(_ value: Int) { traits["smartInsertDelete"] = value }
    @ObjCMethod("textReplacementType") func textReplacementType() -> Int { traits["textReplacement"] ?? 0 }
    @ObjCMethod("setTextReplacementType:") func setTextReplacementType(_ value: Int) { traits["textReplacement"] = value }
    @ObjCMethod("dataDetectionType") func dataDetectionType() -> Int { traits["dataDetection"] ?? 0 }
    @ObjCMethod("setDataDetectionType:") func setDataDetectionType(_ value: Int) { traits["dataDetection"] = value }
    @ObjCMethod("linkDetectionType") func linkDetectionType() -> Int { traits["linkDetection"] ?? 0 }
    @ObjCMethod("setLinkDetectionType:") func setLinkDetectionType(_ value: Int) { traits["linkDetection"] = value }
    @ObjCMethod("textCompletionType") func textCompletionType() -> Int { traits["textCompletion"] ?? 0 }
    @ObjCMethod("setTextCompletionType:") func setTextCompletionType(_ value: Int) { traits["textCompletion"] = value }
    @ObjCMethod("inlinePredictionType") func inlinePredictionType() -> Int { traits["inlinePrediction"] ?? 0 }
    @ObjCMethod("setInlinePredictionType:") func setInlinePredictionType(_ value: Int) { traits["inlinePrediction"] = value }
    @ObjCMethod("mathExpressionCompletionType") func mathExpressionCompletionType() -> Int { traits["mathExpressionCompletion"] ?? 0 }
    @ObjCMethod("setMathExpressionCompletionType:") func setMathExpressionCompletionType(_ value: Int) { traits["mathExpressionCompletion"] = value }
}
