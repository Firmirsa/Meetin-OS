import Foundation
@main struct GoogleProfileSmoke {
 static func main() throws {
  func token(_ metadata: [String: Any]) -> String {
   let data = try! JSONSerialization.data(withJSONObject: ["user_metadata": metadata])
   return "fixture." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + ".fixture"
  }
  precondition(GoogleProfileName.read(accessToken: token(["given_name":"  Léa  ","full_name":"Léa Exemple"])) == "Léa")
  precondition(GoogleProfileName.read(accessToken: token(["name":"Karim Exemple"])) == "Karim Exemple")
  precondition(GoogleProfileName.read(accessToken: token(["name":" "])) == nil)
  precondition(GoogleProfileName.read(accessToken: "malformed") == nil)
  let name = GoogleProfileName.read(accessToken: token(["name":"Léa"])) ?? "Vous"
  var people = MeetingParticipants.newMeeting(localName: name)
  let local = TranscriptSource(track:"microphone",segment:0,session:"a",speaker:nil)
  let diarizedLocal = TranscriptSource(track:"microphone",segment:0,session:"a",speaker:0)
  let remote = TranscriptSource(track:"system",segment:0,session:"a",speaker:nil)
  precondition(people.label(for:local).contains("Léa"))
  precondition(people.label(for:diarizedLocal).contains("Léa"))
  precondition(!people.label(for:remote).contains("Léa"))
  people.people[0].name = "Choix manuel"
  let restored = try JSONDecoder().decode(MeetingParticipants.self,from:JSONEncoder().encode(people))
  precondition(restored.label(for:local).contains("Choix manuel"))
  print("Google profile fallback and local participant smoke passed")
 }
}
