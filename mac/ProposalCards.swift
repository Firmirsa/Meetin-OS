import SwiftUI

// Tâches détectées pendant la réunion. Citron réservé à l'action principale de l'écran : ici, contour uniquement.
struct ProposalCards: View {
    let session: MeetingSession
    let client: AgentClient?
    let showIntegrations: (IntegrationsPage) -> Void

    private var visible: [TaskProposal] { session.proposals.filter { $0.state != .ignored } }

    var body: some View {
        if !visible.isEmpty || session.detector?.lastError != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tâches proposées").font(.mtSerif(28)).accessibilityAddTraits(.isHeader)
                if let error = session.detector?.lastError {
                    Text("Détection interrompue : \(error)").font(.mtSans(13)).foregroundStyle(Color.mtWarn)
                }
                ForEach(visible) { card($0) }
            }
            .padding(.bottom, 12)
        }
    }

    private func card(_ proposal: TaskProposal) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.review.title).font(.mtSans(16, weight: .medium))
                Spacer()
                MTPill(
                    text: proposal.state == .launched ? "Lancée" : "À valider",
                    kind: proposal.state == .launched ? .ok : .run
                )
            }
            Text(proposal.review.task).textSelection(.enabled)
            Text("\(proposal.review.executor.name) · \(proposal.review.destination)")
                .font(.mtSans(13))
                .foregroundStyle(Color.mtInk2)
            if !proposal.review.quote.isEmpty {
                Text("« \(proposal.review.quote) »")
                    .font(.mtSans(13))
                    .foregroundStyle(Color.mtInk2)
                    .textSelection(.enabled)
            }
            if let issue = session.proposalIssues[proposal.id] {
                Text(issue).font(.mtSans(13)).foregroundStyle(Color.mtWarn).textSelection(.enabled)
            }
            if proposal.state == .launched {
                if let url = proposal.sessionURL {
                    Link("Suivre dans \(proposal.review.executor.name)", destination: url)
                }
            } else {
                actions(proposal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .mtGlass()
    }

    private func actions(_ proposal: TaskProposal) -> some View {
        HStack(spacing: 8) {
            if let client {
                Button("Confirmer et lancer") { session.launch(proposal, using: client) }
                    .buttonStyle(.mtGhost)
                    .disabled(session.launchingProposal != nil)
            } else {
                Button("Connecter l’agent") { showIntegrations(.agent) }.buttonStyle(.mtGhost)
            }
            Button("Modifier") { session.edit(proposal) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.mtInk2)
                .padding(.horizontal, 8)
                .disabled(session.agent.busy || session.launchingProposal == proposal.id)
            Button("Ignorer") { session.ignore(proposal) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.mtInk2)
                .disabled(session.launchingProposal == proposal.id)
            if session.launchingProposal == proposal.id {
                ProgressView().controlSize(.small).accessibilityLabel("Lancement en cours")
            }
        }
    }
}
