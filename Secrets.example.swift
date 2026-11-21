// Template for StarGaze/Config/Secrets.swift (that real file is gitignored).
// Copy this file to StarGaze/Config/Secrets.swift and paste in the Gemini API key.

enum Secrets {
    static let geminiAPIKey = "PASTE_GEMINI_API_KEY_HERE"

    // Supabase → Project Settings → API. The publishable (anon) key is safe to ship; RLS protects the data.
    static let supabaseURL = "https://YOUR-PROJECT.supabase.co"
    static let supabaseKey = "PASTE_SUPABASE_PUBLISHABLE_KEY_HERE"
}
