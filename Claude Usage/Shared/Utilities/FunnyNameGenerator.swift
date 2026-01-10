//
//  FunnyNameGenerator.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

struct FunnyNameGenerator {
    static let names = [
        "Quantum Llama", "Sneaky Penguin", "Turbo Sloth", "Cosmic Cat",
        "Digital Dragon", "Ninja Narwhal", "Pixel Panda", "Rocket Raccoon",
        "Thunder Turtle", "Wizard Wombat", "Electric Eel", "Funky Falcon",
        "Galaxy Gopher", "Happy Hippo", "Jazzy Jaguar", "Laser Lemur",
        "Mystic Moose", "Neon Newt", "Psychic Puffin", "Quirky Quokka",
        "Rainbow Rhino", "Stellar Seahorse", "Techno Tiger", "Ultra Unicorn",
        "Vibrant Viper", "Wild Walrus", "Xenon Xerus", "Yolo Yak",
        "Zippy Zebra", "Awesome Axolotl"
    ]

    static func getRandomName(excluding usedNames: [String]) -> String {
        let available = names.filter { !usedNames.contains($0) }
        return available.randomElement() ?? "Profile \(Int.random(in: 1000...9999))"
    }
}
