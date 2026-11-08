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
    var needsAccess = false
    var trelloSetupRequired = false

    func invalidateReview() {
        preparation = nil
        clarifications = []
        answer = ""
        error = ""
        needsAccess = false
        trelloSetupRequired = false
    }

    func newRecording() {
        invalidateReview()
        request = ""
        excerpt = ""
        execution = nil
    }

    func prepare(using client: AgentClient, question: String? = nil) {
        let task = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !task.isEmpty || !transcript.isEmpty else { return }
        var turns = clarifications
        if let question { turns.append(.init(question: question, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))) }
        busy = true
        error = ""
        needsAccess = false
        Task {
            defer { busy = false }
            do {
                preparation = try await client.prepare(task: task, transcript: transcript, clarifications: turns)
                clarifications = turns
                answer = ""
                execution = nil
            } catch {
                needsAccess = (error as? AgentClient.Failure)?.status == 401
                self.error = error.localizedDescription
            }
        }
    }
}

struct AgentWorkspace<Proposals: View>: View {
    @Bindable var state: AgentWorkspaceState
    let transcript: String
    let client: AgentClient?
    let access: AgentAccess?
    let showIntegrations: (IntegrationsPage) -> Void
    @ViewBuilder var proposals: Proposals

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                proposals
                LinkupResearch(client: client, available: access?.linkup)
                Text("Tâche à exécuter").font(.mtSerif(36)).accessibilityAddTraits(.isHeader)
                if client == nil {
                    Text("Vous pouvez préparer votre demande ici. L’accès de l’équipe sera demandé au moment d’utiliser l’agent.")
                        .font(.callout).foregroundStyle(Color.mtInk2)
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
                        .disabled(state.busy || trimmed(state.answer).isEmpty)
                case .review(let review):
                    reviewCard(review)
                case nil:
                    Button("Préparer la tâche") { prepare() }
                        .buttonStyle(.mtPrimary)
                        .disabled(state.busy || (trimmed(state.request).isEmpty && trimmed(state.excerpt).isEmpty))
                }
                if state.busy {
                    if case .review? = state.preparation {
                        ProgressView("En cours").controlSize(.small)
                    } else {
                        ProgressView().controlSize(.small).accessibilityLabel("L’agent traite la demande")
                    }
                }
                if !state.error.isEmpty {
                    Text(state.error).foregroundStyle(Color.mtWarn).textSelection(.enabled)
                }
                if state.needsAccess {
                    Button("Modifier l’accès de l’équipe") { showIntegrations(.agent) }.buttonStyle(.mtGhost)
                }
                if let execution = state.execution {
                    Text("Dernière session lancée").font(.headline)
                    AgentExecutionView(execution: execution, client: client, connect: { showIntegrations(.agent) }) { result in
                        guard state.execution?.trackingToken == execution.trackingToken else { return }
                        state.execution?.trelloResult = result
                    }
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
            if review.usesTrello && (access?.trello == false || state.trelloSetupRequired) {
                Text("Votre équipe doit relier Trello. La proposition reste disponible ici.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
                Button("Voir l’accès Trello") { showIntegrations(.catalog) }.buttonStyle(.mtPrimary)
            } else if review.executor == .devin && access?.devin == false {
                Text("Votre équipe doit activer Devin avant de lancer cette tâche.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
                Button("Voir l’accès Devin") { showIntegrations(.catalog) }.buttonStyle(.mtPrimary)
            } else {
                Button("Confirmer et lancer") { launch(review) }.buttonStyle(.mtPrimary).disabled(state.busy || client == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtCard()
    }

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func prepare(question: String? = nil) {
        if state.needsAccess || client == nil {
            showIntegrations(question == nil ? .prepare : .agent)
        } else if access?.planning == false {
            showIntegrations(.catalog)
        } else if let client {
            state.prepare(using: client, question: question)
        }
    }

    private func launch(_ review: AgentReview) {
        guard let client, !state.busy else { return }
        state.busy = true
        state.error = ""
        Task {
            defer { state.busy = false }
            do {
                state.execution = try await client.launch(review)
                state.preparation = nil
            } catch {
                let failure = error as? AgentClient.Failure
                state.needsAccess = failure?.status == 401
                state.trelloSetupRequired = failure?.code == "trello_setup"
                if !state.needsAccess && !state.trelloSetupRequired { state.preparation = nil }
                state.error = error.localizedDescription
            }
        }
    }
}
