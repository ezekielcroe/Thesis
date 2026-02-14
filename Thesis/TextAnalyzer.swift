import Foundation
import NaturalLanguage

struct TextUnit {
    let range: NSRange
    let text: String
}

class TextAnalyzer {
    
    // MARK: - Sentence Detection
    
    static func getSentences(in text: String) -> [TextUnit] {
        var sentences: [TextUnit] = []
        let nsText = text as NSString
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .sentence,
                            scheme: .lexicalClass) { _, range in
            let nsRange = NSRange(range, in: text)
            let sentenceText = nsText.substring(with: nsRange)
            sentences.append(TextUnit(range: nsRange, text: sentenceText))
            return true
        }
        
        return sentences
    }
    
    static func getSentenceAt(position: Int, in text: String) -> TextUnit? {
        let sentences = getSentences(in: text)
        return sentences.first { NSLocationInRange(position, $0.range) }
    }
    
    static func getNextSentence(from position: Int, in text: String) -> TextUnit? {
        let sentences = getSentences(in: text)
        return sentences.first { $0.range.location > position }
    }
    
    static func getPreviousSentence(from position: Int, in text: String) -> TextUnit? {
        let sentences = getSentences(in: text)
        return sentences.last { $0.range.location < position }
    }
    
    // MARK: - Clause Detection
    
    static func getClauses(in text: String) -> [TextUnit] {
        var clauses: [TextUnit] = []
        let sentences = getSentences(in: text)
        let nsText = text as NSString
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        
        for sentence in sentences {
            tagger.string = sentence.text
            var lastBoundary = 0
            
            tagger.enumerateTags(in: sentence.text.startIndex..<sentence.text.endIndex,
                                unit: .word,
                                scheme: .lexicalClass) { tag, range in
                
                let wordRange = NSRange(range, in: sentence.text)
                let word = (sentence.text as NSString).substring(with: wordRange).lowercased()
                
                // Define boundaries: Punctuation or Conjunctions
                let isBoundaryPunctuation = (tag == .punctuation && (word == "," || word == ";" || word == ":"))
                let isConjunction = (tag == .conjunction)
                
                if isBoundaryPunctuation || isConjunction {
                    let length = wordRange.location - lastBoundary
                    if length > 0 {
                        let clauseRange = NSRange(location: sentence.range.location + lastBoundary, length: length)
                        clauses.append(TextUnit(range: clauseRange, text: nsText.substring(with: clauseRange)))
                    }
                    lastBoundary = wordRange.location
                }
                return true
            }
            
            // Add the final trailing clause of the sentence
            let finalLength = sentence.range.length - lastBoundary
            if finalLength > 0 {
                let finalRange = NSRange(location: sentence.range.location + lastBoundary, length: finalLength)
                clauses.append(TextUnit(range: finalRange, text: nsText.substring(with: finalRange)))
            }
        }
        return clauses
    }
    
    // MARK: - Paragraph Detection
    
    static func getParagraphs(in text: String) -> [TextUnit] {
        var paragraphs: [TextUnit] = []
        let nsText = text as NSString
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .paragraph,
                            scheme: .lexicalClass) { _, range in
            let nsRange = NSRange(range, in: text)
            let paragraphText = nsText.substring(with: nsRange)
            
            // Only include non-empty paragraphs
            if !paragraphText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                paragraphs.append(TextUnit(range: nsRange, text: paragraphText))
            }
            return true
        }
        
        return paragraphs
    }
    
    static func getParagraphAt(position: Int, in text: String) -> TextUnit? {
        let paragraphs = getParagraphs(in: text)
        return paragraphs.first { NSLocationInRange(position, $0.range) }
    }
    
    static func getNextParagraph(from position: Int, in text: String) -> TextUnit? {
        let paragraphs = getParagraphs(in: text)
        return paragraphs.first { $0.range.location > position }
    }
    
    static func getPreviousParagraph(from position: Int, in text: String) -> TextUnit? {
        let paragraphs = getParagraphs(in: text)
        return paragraphs.last { $0.range.location < position }
    }
    
    // MARK: - Word Detection
    
    static func getWords(in text: String) -> [TextUnit] {
        var words: [TextUnit] = []
        let nsText = text as NSString
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .lexicalClass) { _, range in
            let nsRange = NSRange(range, in: text)
            let wordText = nsText.substring(with: nsRange)
            words.append(TextUnit(range: nsRange, text: wordText))
            return true
        }
        
        return words
    }
    
    static func getWordAt(position: Int, in text: String) -> TextUnit? {
        let words = getWords(in: text)
        return words.first { NSLocationInRange(position, $0.range) }
    }
    
    static func getNextWord(from position: Int, in text: String) -> TextUnit? {
        let words = getWords(in: text)
        return words.first { $0.range.location > position }
    }
    
    static func getPreviousWord(from position: Int, in text: String) -> TextUnit? {
        let words = getWords(in: text)
        return words.last { $0.range.location < position }
    }
    
    // MARK: - Helper Methods
    
    static func getRestOfSentence(from position: Int, in text: String) -> TextUnit? {
        guard let sentence = getSentenceAt(position: position, in: text) else { return nil }
        
        let restStart = position
        let restEnd = sentence.range.location + sentence.range.length
        let restRange = NSRange(location: restStart, length: restEnd - restStart)
        
        let nsText = text as NSString
        let restText = nsText.substring(with: restRange)
        
        return TextUnit(range: restRange, text: restText)
    }
    
    // MARK: - Additional Helper for Word Boundaries
    
    static func getForwardWord(from position: Int, in text: String) -> TextUnit? {
        let words = getWords(in: text)
        
        // Find the word that starts at or after the current position
        if let currentWord = words.first(where: { $0.range.location >= position }) {
            return currentWord
        }
        
        // If cursor is inside a word, get the next word
        return words.first { $0.range.location > position }
    }
    
    static func getBackwardWord(from position: Int, in text: String) -> TextUnit? {
        let words = getWords(in: text)
        
        // Find the word that ends at or before the current position
        return words.last { $0.range.location + $0.range.length <= position }
    }
}
