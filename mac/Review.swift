import AppKit
import Foundation
import Observation
import SwiftUI

// Écran après la réunion : le carnet à gauche, les engagements à valider à droite.
// Même design que la page Réunion du site (web/app/reunions/[id]) et même logique que web/lib/contract.mjs.
// Contrat front ↔ agent : docs/contrat-front-agent.md. L'agent est simulé : pour brancher la vraie route,
// remplace `agentResult(for:)` par un appel réseau.

// MARK: - Contrat

struct ReviewExcerpt: Codable, Equatable {
    var text: String
    var startMs: Int
    var endMs: Int
}

struct ReviewProposal: Codable, Equatable {
    var proposalId: String
    var title: String
    var assignee: String?
    var dueDate: String?
    var excerpt: ReviewExcerpt
}

struct ReviewValidation: Codable, Equatable {
    var validationId: String
    var proposalId: String
    var title: String
    var assignee: String
    var dueDate: String?
}

struct ReviewObserved: Codable, Equatable {
    var title: String
    var assignee: String
    var dueDate: String?
}

enum ReviewExecution: Equatable {
    case pending(validationId: String)
    case verified(validationId: String, taskURL: String, observed: ReviewObserved)
    case needsClarification(validationId: String, message: String)
    case failed(validationId: String, message: String)
}

enum ReviewScenario: String, CaseIterable, Identifiable {
    case verified, ambigu, failed
    var id: Self { self }
    var label: String {
        switch self {
        case .verified: return "Fiche mise à jour"
        case .ambigu: return "Fiche ambiguë"
        case .failed: return "Échec puis relance"
        }
    }
}

// MARK: - Données de démo (copie de web/lib/reunions-demo.json, réunion « Point de lancement »)

enum ReviewDemo {
    static let fixtureProposalId = "proposal-demo-001"
    static let taskURL = "https://example.com/tasks/demo-42"
    static let clarification = "Deux fiches correspondent à « Relire le guide de lancement ». Précisez le projet."
    static let failure = "La fiche n’a pas pu être relue après la mise à jour."

    static let proposals: [ReviewProposal] = [
        ReviewProposal(
            proposalId: "proposal-demo-001", title: "Relire le guide de lancement", assignee: "Karim", dueDate: "2026-11-10",
            excerpt: ReviewExcerpt(text: "Léa devait relire le guide. Finalement, Karim s’en charge mardi.", startMs: 18000, endMs: 24000)),
        ReviewProposal(
            proposalId: "proposal-demo-002", title: "Envoyer le devis à Atlas", assignee: "Léa", dueDate: "2026-11-12",
            excerpt: ReviewExcerpt(text: "Je m’en occupe, j’envoie le devis à Atlas jeudi.", startMs: 763000, endMs: 768000)),
        ReviewProposal(
            proposalId: "proposal-demo-003", title: "Préparer la démo pour le jury", assignee: nil, dueDate: nil,
            excerpt: ReviewExcerpt(text: "Il faudrait que quelqu’un prépare la démo pour le jury, on verra qui.", startMs: 1534000, endMs: 1540000)),
    ]
}

// MARK: - Formats

enum ReviewFormat {
    /// Millisecondes depuis le début de l'audio → « mm:ss ».
    static func time(_ ms: Int) -> String {
        let total = max(0, ms / 1000)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// « YYYY-MM-DD » → date locale à midi, pour éviter tout décalage de fuseau.
    static func date(fromCivil value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func civil(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func french(_ pattern: String, _ value: String?, empty: String) -> String {
        guard let value, let date = date(fromCivil: value) else { return empty }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// « 2026-11-10 » → « mardi 10 novembre 2026 ».
    static func due(_ value: String?) -> String { french("EEEE d MMMM yyyy", value, empty: "Aucune") }

    /// « 2026-11-10 » → « mar. 10 nov. », pour les cartes repliées.
    static func dueShort(_ value: String?) -> String { french("EEE d MMM", value, empty: "Sans échéance") }

    /// Sépare la dernière phrase de l'extrait pour la passer au surligneur.
    static func splitExcerpt(_ text: String) -> (before: String, highlight: String) {
        var cut: String.Index?
        for separator in [". ", "! ", "? ", "… "] {
            if let range = text.range(of: separator, options: .backwards), cut.map({ range.upperBound > $0 }) ?? true {
                cut = range.upperBound
            }
        }
        guard let cut else { return ("", text) }
        return (String(text[..<cut]).trimmingCharacters(in: .whitespaces), String(text[cut...]))
    }
}

// MARK: - Un engagement

struct EngagementItem: Identifiable {
    let proposal: ReviewProposal
    let initialDue: Date
    var commitment: MTCommitment
    var reviewState: MTReviewState = .proposed
    var validation: ReviewValidation?
    var execution: ReviewExecution?
    var replayed = false
    /// Étapes et preuve stockées : identifiants stables pour ForEach, seuls les statuts changent.
    var steps: [MTAgentStep]
    var proof: [MTProofRow] = []
    var notice: String?

    var id: String { proposal.proposalId }

    init(proposal: ReviewProposal) {
        self.proposal = proposal
        let due = proposal.dueDate.flatMap(ReviewFormat.date(fromCivil:))
            ?? Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        initialDue = due
        let parts = ReviewFormat.splitExcerpt(proposal.excerpt.text)
        commitment = MTCommitment(
            title: proposal.title,
            owner: proposal.assignee ?? "",
            due: due,
            quoteBefore: parts.before,
            quoteHighlight: parts.highlight,
            timestamp: "\(ReviewFormat.time(proposal.excerpt.startMs)) – \(ReviewFormat.time(proposal.excerpt.endMs))",
            speakers: "extrait source, non modifiable")
        steps = EngagementsModel.makeSteps(title: proposal.title, assignee: proposal.assignee ?? "", due: proposal.dueDate)
    }

    /// Une échéance inconnue reste `null` tant que l'utilisateur ne la change pas.
    var dueValue: String? {
        if proposal.dueDate == nil && commitment.due == initialDue { return nil }
        return ReviewFormat.civil(commitment.due)
    }

    var isSending: Bool {
        if case .pending = execution { return true }
        return false
    }

    var isVerified: Bool {
        if case .verified = execution { return true }
        return false
    }

    var summary: String {
        let owner = commitment.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(owner.isEmpty ? "Responsable à préciser" : owner) · \(ReviewFormat.dueShort(dueValue))"
    }

    /// Pastille de la carte : état de la revue, puis de l'exécution.
    var pill: (text: String, kind: MTPillKind) {
        if reviewState == .ignored { return ("Ignoré", .wait) }
        switch execution {
        case nil: return ("À valider", .wait)
        case .pending: return ("En cours", .run)
        case .verified: return ("Fiche à jour", .ok)
        case .needsClarification: return ("Précision requise", .err)
        case .failed: return ("Échec", .err)
        }
    }

    /// Pastille du suivi de l'agent.
    var agentPill: (text: String, kind: MTPillKind) {
        switch execution {
        case nil: return ("En attente de validation", .wait)
        case .pending: return ("En cours", .run)
        case .verified: return ("Terminé", .ok)
        case .needsClarification: return ("Précision requise", .err)
        case .failed: return ("Échec", .err)
        }
    }
}

// MARK: - Modèle

@MainActor
@Observable
final class EngagementsModel {
    static let stepCount = 5

    private(set) var scenario: ReviewScenario = .verified
    var items: [EngagementItem]
    var openId: String?

    // Agent simulé, partagé par toutes les cartes et idempotent par validationId.
    private var results: [String: ReviewExecution] = [:]
    private var firstId: String?
    private var attempts = 0
    private var generation = 0

    init() {
        items = ReviewDemo.proposals.map(EngagementItem.init(proposal:))
        openId = items.first?.id
    }

    nonisolated static func makeSteps(title: String, assignee: String, due: String?) -> [MTAgentStep] {
        [
            MTAgentStep(title: "Retrouve la fiche « \(title) »", meta: "Tableau de suivi"),
            MTAgentStep(title: "Ouvre la fiche"),
            MTAgentStep(title: "Passe le responsable à \(assignee.isEmpty ? "…" : assignee)"),
            MTAgentStep(title: due.map { "Fixe l’échéance au \(ReviewFormat.due($0))" } ?? "Laisse l’échéance vide"),
            MTAgentStep(title: "Relit la fiche pour vérifier"),
        ]
    }

    var todoCount: Int { items.filter { $0.reviewState != .ignored && !$0.isVerified }.count }
    var isAnySending: Bool { items.contains { $0.isSending } }

    private func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }

    // MARK: Actions

    func select(_ scenario: ReviewScenario) {
        self.scenario = scenario
        generation += 1
        items = ReviewDemo.proposals.map(EngagementItem.init(proposal:))
        openId = items.first?.id
        results = [:]
        firstId = nil
        attempts = 0
    }

    func toggle(_ id: String) {
        openId = openId == id ? nil : id
    }

    func validate(_ id: String) {
        guard let i = index(of: id) else { return }
        let title = items[i].commitment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignee = items[i].commitment.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !assignee.isEmpty else {
            items[i].reviewState = .proposed
            items[i].notice = "Personne n’a été désigné. Renseigne le titre et le responsable pour pouvoir valider."
            return
        }
        guard !items[i].isSending else { return }
        items[i].notice = nil
        let due = items[i].dueValue
        // Même contenu que la dernière validation → même UUID. Contenu modifié → nouvel UUID.
        let validationId: String
        if let previous = items[i].validation, previous.title == title, previous.assignee == assignee, previous.dueDate == due {
            validationId = previous.validationId
        } else {
            validationId = UUID().uuidString.lowercased()
        }
        send(id, ReviewValidation(validationId: validationId, proposalId: id, title: title, assignee: assignee, dueDate: due))
    }

    func retry(_ id: String) {
        guard let i = index(of: id), let validation = items[i].validation, case .failed = items[i].execution else { return }
        send(id, validation)
    }

    func replay(_ id: String) {
        guard let i = index(of: id), let validation = items[i].validation, items[i].isVerified else { return }
        send(id, validation, replay: true)
    }

    func resume(_ id: String) {
        guard let i = index(of: id) else { return }
        items[i].reviewState = .proposed
    }

    func openRecord(_ id: String) {
        guard let i = index(of: id), case .verified(_, let link, _) = items[i].execution,
              let url = URL(string: link), url.scheme == "https" || url.scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }

    func play(_ id: String) {
        guard let i = index(of: id) else { return }
        items[i].notice = "L’écoute de l’extrait sera branchée sur l’enregistrement de la réunion."
    }

    private func send(_ id: String, _ next: ReviewValidation, replay: Bool = false) {
        guard let i = index(of: id), !items[i].isSending else { return }
        let token = generation
        if items[i].validation != next {
            items[i].steps = Self.makeSteps(title: next.title, assignee: next.assignee, due: next.dueDate)
        }
        items[i].validation = next
        items[i].replayed = false
        items[i].proof = []
        items[i].execution = .pending(validationId: next.validationId)
        applyStatuses(i, running: 0)
        Task { [weak self] in
            for step in 1..<EngagementsModel.stepCount {
                try? await Task.sleep(for: .milliseconds(280))
                guard let self, self.generation == token, let j = self.index(of: id) else { return }
                self.applyStatuses(j, running: step)
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.generation == token, let j = self.index(of: id) else { return }
            let (result, wasReplay) = self.agentResult(for: next)
            self.items[j].execution = result
            self.items[j].replayed = replay && wasReplay
            self.applyStatuses(j, running: EngagementsModel.stepCount)
            switch result {
            case .verified(_, _, let observed):
                self.items[j].proof = [
                    MTProofRow(label: "Titre", before: "", after: observed.title),
                    MTProofRow(label: "Responsable", before: "", after: observed.assignee),
                    MTProofRow(label: "Échéance", before: "", after: ReviewFormat.due(observed.dueDate)),
                ]
                if !replay { self.openNext(after: id, token: token) }
            case .needsClarification(_, let message):
                // Cible ambiguë : la carte redevient modifiable pour que l'utilisateur précise.
                self.items[j].reviewState = .proposed
                self.items[j].notice = "\(message) Corrige le titre pour désigner la bonne fiche, puis valide à nouveau."
            default:
                break
            }
        }
    }

    /// Laisse voir la fiche vérifiée, puis ouvre l'engagement suivant à valider.
    private func openNext(after id: String, token: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, self.generation == token, self.openId == id else { return }
            if let next = self.items.first(where: { $0.reviewState != .ignored && !$0.isVerified && !$0.isSending }) {
                self.openId = next.id
            }
        }
    }

    /// Met à jour les statuts des étapes sans recréer les étapes.
    private func applyStatuses(_ i: Int, running: Int) {
        let last = Self.stepCount - 1
        for index in items[i].steps.indices {
            var status = MTStepStatus.pending
            var meta: String? = index == 0 ? "Tableau de suivi" : nil
            switch items[i].execution {
            case .pending:
                status = index < running ? .done : (index == running ? .running : .pending)
            case .verified:
                status = .done
            case .needsClarification:
                if index == 0 { status = .error; meta = "Plusieurs fiches correspondent" }
            case .failed(_, let message):
                status = index < last ? .done : .error
                if index == last { meta = message }
            case nil:
                break
            }
            items[i].steps[index].status = status
            items[i].steps[index].meta = meta
        }
    }

    private func agentResult(for validation: ReviewValidation) -> (ReviewExecution, Bool) {
        let id = validation.validationId
        if let known = results[id], case .verified = known { return (known, true) }
        attempts += 1
        if firstId == nil { firstId = id }
        let isFixture = validation.proposalId == ReviewDemo.fixtureProposalId
        let result: ReviewExecution
        if scenario == .ambigu && id == firstId {
            let message = isFixture
                ? ReviewDemo.clarification
                : "Deux fiches correspondent à « \(validation.title) ». Précisez le projet."
            result = .needsClarification(validationId: id, message: message)
        } else if scenario == .failed && attempts == 1 {
            result = .failed(validationId: id, message: ReviewDemo.failure)
        } else {
            result = .verified(
                validationId: id,
                taskURL: isFixture ? ReviewDemo.taskURL : "https://example.com/tasks/\(validation.proposalId)",
                observed: ReviewObserved(title: validation.title, assignee: validation.assignee, dueDate: validation.dueDate))
        }
        results[id] = result
        return (result, false)
    }
}

// MARK: - Vues

enum NotebookTab: Hashable { case notes, transcript }

/// Carnet à gauche, engagements à droite. Sous ~750 pt de large, tout passe en une colonne.
struct AfterMeetingView: View {
    let notes: String
    let transcript: String
    @Bindable var model: EngagementsModel
    @State private var tab: NotebookTab = .notes

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                NotebookPanel(notes: notes, transcript: transcript, tab: $tab)
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity, alignment: .topLeading)
                EngagementsColumn(model: model, onShowTranscript: { tab = .transcript })
                    .frame(width: 340)
            }
            VStack(alignment: .leading, spacing: 28) {
                NotebookPanel(notes: notes, transcript: transcript, tab: $tab)
                EngagementsColumn(model: model, onShowTranscript: { tab = .transcript })
            }
        }
    }
}

struct NotebookPanel: View {
    let notes: String
    let transcript: String
    @Binding var tab: NotebookTab

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Vue du carnet", selection: $tab) {
                Text("Notes").tag(NotebookTab.notes)
                Text("Transcription").tag(NotebookTab.transcript)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch tab {
            case .notes:
                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Tes notes de réunion apparaîtront ici.")
                        .foregroundStyle(Color.mtInk2)
                } else {
                    Text(notes)
                        .font(.mtSans(16))
                        .foregroundStyle(Color.mtInk)
                        .textSelection(.enabled)
                }
            case .transcript:
                if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Lance « Transcrire » pour retrouver ici ce qui a été dit.")
                        .foregroundStyle(Color.mtInk2)
                } else {
                    Text(transcript)
                        .font(.mtSans(15))
                        .lineSpacing(4)
                        .foregroundStyle(Color.mtInk)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EngagementsColumn: View {
    @Bindable var model: EngagementsModel
    var onShowTranscript: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Engagements").font(.mtSerif(26)).accessibilityAddTraits(.isHeader)
                Spacer()
                MTPill(text: model.todoCount > 0 ? "\(model.todoCount) à valider" : "Tout est traité",
                       kind: model.todoCount > 0 ? .run : .ok)
            }
            HStack {
                Text("Données de démo").font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                Spacer()
                Picker("Démo", selection: Binding(get: { model.scenario }, set: { model.select($0) })) {
                    ForEach(ReviewScenario.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(model.isAnySending)
            }
            ForEach($model.items) { $item in
                EngagementRow(
                    item: $item,
                    isOpen: model.openId == item.id,
                    onToggle: { model.toggle(item.id) },
                    onValidate: { model.validate(item.id) },
                    onRetry: { model.retry(item.id) },
                    onReplay: { model.replay(item.id) },
                    onResume: { model.resume(item.id) },
                    onOpenRecord: { model.openRecord(item.id) },
                    onPlay: { model.play(item.id) },
                    onShowTranscript: onShowTranscript)
            }
        }
    }
}

/// Repliée : titre, responsable, échéance, état. Ouverte : la carte du brand, avec le seul bouton citron.
struct EngagementRow: View {
    @Binding var item: EngagementItem
    let isOpen: Bool
    let onToggle: () -> Void
    let onValidate: () -> Void
    let onRetry: () -> Void
    let onReplay: () -> Void
    let onResume: () -> Void
    let onOpenRecord: () -> Void
    let onPlay: () -> Void
    let onShowTranscript: () -> Void

    var body: some View {
        if isOpen {
            VStack(alignment: .leading, spacing: 10) {
                MTReviewCard(item: $item.commitment, state: $item.reviewState, onValidate: onValidate, onPlay: onPlay)
                    .disabled(item.isSending)
                HStack(spacing: 14) {
                    Button("\(ReviewFormat.time(item.proposal.excerpt.startMs)) · Voir dans la transcription", action: onShowTranscript)
                        .buttonStyle(.plain)
                        .font(.mtSans(13, weight: .medium))
                        .foregroundStyle(Color.mtAccentText)
                        .underline()
                    Spacer()
                    Button("Replier", systemImage: "chevron.up", action: onToggle)
                        .buttonStyle(.plain)
                        .font(.mtSans(13))
                        .foregroundStyle(Color.mtInk2)
                }
                if item.reviewState == .ignored {
                    Button("Reprendre", action: onResume).buttonStyle(.mtGhost)
                }
                if let notice = item.notice {
                    Text(notice)
                        .font(.mtSans(13))
                        .foregroundStyle(Color.mtWarn)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.mtWarnTint, in: RoundedRectangle(cornerRadius: MTRadius.input))
                }
                if item.execution != nil {
                    MTAgentTimeline(
                        steps: item.steps,
                        statusText: item.agentPill.text,
                        statusKind: item.agentPill.kind,
                        proof: item.proof,
                        alreadyUpToDate: item.replayed,
                        onOpenRecord: onOpenRecord)
                }
                switch item.execution {
                case .failed(_, let message):
                    HStack(spacing: 12) {
                        Text(message).font(.mtSans(14)).foregroundStyle(Color.mtRec)
                        Spacer()
                        Button("Relancer", action: onRetry).buttonStyle(.mtGhost)
                    }
                case .verified:
                    Button("Rejouer la validation", action: onReplay).buttonStyle(.mtGhost)
                default:
                    EmptyView()
                }
            }
        } else {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.commitment.title).font(.mtSerif(19)).foregroundStyle(Color.mtInk)
                        Text(item.summary).font(.mtSans(13)).foregroundStyle(Color.mtInk2)
                    }
                    Spacer(minLength: 8)
                    MTPill(text: item.pill.text, kind: item.pill.kind, onCard: true)
                }
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mtSurface, in: RoundedRectangle(cornerRadius: MTRadius.card))
                .contentShape(RoundedRectangle(cornerRadius: MTRadius.card))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre l’engagement")
        }
    }
}
