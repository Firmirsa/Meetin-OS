import AppKit
import SwiftUI

@MainActor
@Observable
final class AgentWorkspaceState {
    var request = ""
    var excerpt = ""
    var answer = ""
    var preparation: AgentPreparation?
    var execution: AgentExecution?
    var clarifications: [AgentClarification] = []
    var busy = false
    var error = ""

    func invalidateReview() {
        preparation = nil
        clarifications = []
        answer = ""
        error = ""
    }

    func newRecording() {
        invalidateReview()
        request = ""
        excerpt = ""
        execution = nil
    }
}

struct AgentWorkspace: View {
    @Bindable var state: AgentWorkspaceState
    let transcript: String
    let client: AgentClient?
    let showSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tâche à exécuter").font(.mtSerif(36)).accessibilityAddTraits(.isHeader)
                if client == nil {
                    Button("Configurer l’accès agent", action: showSettings).buttonStyle(.mtGhost)
                }
                TextField("Demande", text: $state.request, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.busy)
                    .onChange(of: state.request) { state.invalidateReview() }
                Text("Extrait de réunion").font(.headline)
                TextEditor(text: $state.excerpt)
                    .accessibilityLabel("Extrait de réunion")
                    .frame(minHeight: 80, maxHeight: 110)
                    .disabled(state.busy)
                    .onChange(of: state.excerpt) { state.invalidateReview() }
                if !transcript.isEmpty {
                    Button(transcript.count > 5_000 ? "Insérer le début de la transcription" : "Insérer la transcription") {
                        state.excerpt = String(transcript.prefix(5_000))
                    }
                        .disabled(state.busy)
                }
                Text("Préparer envoie la demande et l’extrait sélectionné à Holo (H Company).")
                    .font(.callout).foregroundStyle(Color.mtInk2)
                switch state.preparation {
                case .question(let question):
                    Text(question).font(.headline)
                    TextField("Votre précision", text: $state.answer, axis: .vertical)
                        .textFieldStyle(.roundedBorder).disabled(state.busy)
                    Button("Ajouter cette précision") { prepare(question: question) }
                        .buttonStyle(.mtPrimary)
                        .disabled(state.busy || client == nil || trimmed(state.answer).isEmpty)
                case .review(let review):
                    reviewCard(review)
                case nil:
                    Button("Préparer la tâche") { prepare() }
                        .buttonStyle(.mtPrimary)
                        .disabled(state.busy || client == nil || (trimmed(state.request).isEmpty && trimmed(state.excerpt).isEmpty))
                }
                if state.busy { ProgressView().controlSize(.small).accessibilityLabel("L’agent traite la demande") }
                if !state.error.isEmpty {
                    Text(state.error).foregroundStyle(Color.mtWarn).textSelection(.enabled)
                }
                if let execution = state.execution {
                    Text("Dernière session lancée").font(.headline)
                    Link("Suivre dans \(execution.executor.name)", destination: execution.url)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func reviewCard(_ review: AgentReview) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("À confirmer").font(.headline)
            Text(review.title).font(.mtSans(17, weight: .semibold))
            Text(review.task).textSelection(.enabled)
            Text("\(review.executor.name) · \(review.destination)").foregroundStyle(Color.mtInk2)
            if !review.quote.isEmpty { Text(review.quote).font(.callout).textSelection(.enabled) }
            ForEach(Array(review.clarifications.enumerated()), id: \.offset) { _, turn in
                Text("\(turn.question) \(turn.answer)").font(.callout)
            }
            Button("Confirmer et lancer") { launch(review) }.buttonStyle(.mtPrimary).disabled(state.busy || client == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtCard()
    }

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func prepare(question: String? = nil) {
        guard let client, !state.busy else { return }
        let task = trimmed(state.request)
        let excerpt = trimmed(state.excerpt)
        var turns = state.clarifications
        if let question { turns.append(.init(question: question, answer: trimmed(state.answer))) }
        state.busy = true
        state.error = ""
        Task {
            defer { state.busy = false }
            do {
                state.preparation = try await client.prepare(task: task, transcript: excerpt, clarifications: turns)
                state.clarifications = turns
                state.answer = ""
                state.execution = nil
            } catch { state.error = error.localizedDescription }
        }
    }

    private func launch(_ review: AgentReview) {
        guard let client, !state.busy else { return }
        state.busy = true
        state.error = ""
        Task {
            defer { state.busy = false; state.preparation = nil }
            do { state.execution = try await client.launch(review) }
            catch { state.error = error.localizedDescription }
        }
    }
}
