import Foundation
import MobileCoreServices


// MARK: - URLExtractor
//
struct URLExtractor: Extractor {

    /// Accepted File Extension
    ///
    let acceptedType = kUTTypeURL as String

    /// Indicates if a given Extension Context can be handled by the Extractor
    ///
    func canHandle(context: NSExtensionContext) -> Bool {
        return context.itemProviders(ofType: acceptedType).isEmpty == false
    }

    /// Extracts a Note entity contained within a given Extension Context (If possible!)
    ///
    func extractNote(from context: NSExtensionContext, onCompletion: @escaping (Note?) -> Void) {
        guard let provider = context.itemProviders(ofType: acceptedType).first else {
            onCompletion(nil)
            return
        }

        provider.loadItem(forTypeIdentifier: acceptedType, options: nil) { (payload, _) in
            guard let url = payload as? URL else {
                onCompletion(nil)
                return
            }

            let note = self.loadNote(from: url) ?? self.buildExternalLinkNote(with: url, context: context)
            onCompletion(note)
        }
    }
}


// MARK: - Loading Notes from a file!
//
private extension URLExtractor {

    /// Loads the contents from the specified file, and returns a Note instance with its contents
    ///
    func loadNote(from url: URL) -> Note? {
        guard let `extension` = SupportedPathExtension(rawValue: url.pathExtension) else {
            return nil
        }

        switch `extension` {
        case .textpack:
            return loadTextPack(from: url)
        case .textbundle:
            return loadTextBundle(from: url)
        case .text, .txt:
            return loadContents(from: url)
        case .markdown, .md:
            return loadContents(from: url, isMarkdown: true)
        }
    }

    ///
    ///
    func loadTextPack(from url: URL) -> Note {
// TODO
        return Note(content: "TextPack")
    }

    /// Loads a TextBundle file from the specified URL.
    ///
    func loadTextBundle(from url: URL) -> Note {
        let bundleWrapper = TextBundleWrapper(contentsOf: url, options: .immediate, error: nil)
        let isMarkdownNote = bundleWrapper.type == kUTTypeMarkdown

        return Note(content: bundleWrapper.text, markdown: isMarkdownNote)
    }

    /// Loads the String contents from a given URL.
    ///
    func loadContents(from url: URL, isMarkdown: Bool = false) -> Note? {
        guard let content = try? String(contentsOf: url) else {
            return nil
        }

        return Note(content: content, markdown: isMarkdown)
    }
}


// MARK: - Fallback: Handling external URL(s)
//
private extension URLExtractor {

    ///
    ///
    func buildExternalLinkNote(with url: URL, context: NSExtensionContext) -> Note? {
        guard url.isFileURL == false, let payload = context.attributedContentText?.string else {
            return nil
        }

        let content = payload + "\n\n[" + url.absoluteString + "]"
        return Note(content: content)
    }
}


// MARK: - URLExtension
//
private enum SupportedPathExtension: String {
    case textbundle
    case textpack
    case text
    case txt
    case markdown
    case md
}
