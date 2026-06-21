#!/usr/bin/env swift
import Foundation

// Normalises a String Catalog (.xcstrings) to Xcode's exact on-disk format so the file
// stops churning every time Xcode touches it. Xcode's String Catalog editor saves via
// Foundation's JSONSerialization with `.prettyPrinted` + `.sortedKeys` (space before the
// colon, expanded empty objects, keys sorted, slashes & non-ASCII left literal). When we
// hand-edit the catalog we tend to write a compact, unsorted form — re-running this restores
// the canonical format so git diffs stay clean.
//
// Usage:  swift scripts/normalize-xcstrings.swift [path]
// Default path: AIFitnessCoach/Localizable.xcstrings
//
// Run this after any hand-edit of the catalog (see CLAUDE.md §13).

let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AIFitnessCoach/Localizable.xcstrings"

let url = URL(fileURLWithPath: path)
do {
    let data = try Data(contentsOf: url)
    let obj = try JSONSerialization.jsonObject(with: data)
    let out = try JSONSerialization.data(
        withJSONObject: obj,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    var str = String(data: out, encoding: .utf8)!
    if !str.hasSuffix("\n") { str += "\n" }
    try str.write(to: url, atomically: true, encoding: .utf8)
    print("Normalised \(path)")
} catch {
    FileHandle.standardError.write(Data("normalize-xcstrings failed: \(error)\n".utf8))
    exit(1)
}
