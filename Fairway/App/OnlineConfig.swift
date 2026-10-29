import Foundation

/// Build-time online play settings.
///
/// Fill these in to give everyone who installs your build online matches and tournaments
/// without typing anything. The anon key is public by design; row-level security in
/// `supabase/schema.sql` protects the data. Players can still override these in
/// Settings → Online Play. Leave them empty to ship in offline demo mode.
enum OnlineConfig {
    /// Your Supabase project ref ("abcdefghijkl") or URL.
    static let supabaseProject = ""
    /// Project Settings → API → "anon public" key.
    static let supabaseAnonKey = ""
}
