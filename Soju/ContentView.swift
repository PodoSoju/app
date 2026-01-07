//
//  ContentView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "wineglass")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Welcome to Soju")
                .font(.largeTitle)
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
