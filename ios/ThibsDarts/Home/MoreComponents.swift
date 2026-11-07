import SwiftUI

/// Avatar rond : photo (locale ou servie par le Pi) ou initiales (Avatar du design system).
struct Avatar: View {
    let name: String
    var image: UIImage?
    var url: URL?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Td.asphalteHaut)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { initials }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Td.verreBord))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return Text(String(parts).uppercased())
            .font(.tdRounded(size * 0.38, .heavy))
            .foregroundStyle(Td.ink)
    }
}

/// Carte joueur (PlayerCard) avec message "Hôte", "Prêt".
struct PlayerCardView: View {
    let name: String
    var image: UIImage?
    var url: URL?
    var message: String?
    var ready = false

    var body: some View {
        HStack(spacing: Td.s3) {
            Avatar(name: name, image: image, url: url)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.td(17, .semibold)).lineLimit(1)
                if let message {
                    HStack(spacing: Td.s1) {
                        Icon(name: .check, size: 12)
                        Text(message).font(.td(13))
                    }
                    .foregroundStyle(ready ? Td.succes : Td.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Td.s3)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.verreLeger))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(ready ? Td.succes : Td.verreBord))
    }
}

/// Barre d'onglets en verre (TabBar).
struct TabBar: View {
    struct Item: Identifiable {
        let id: String
        let icon: LucideIcon
        let label: String
    }

    let items: [Item]
    @Binding var value: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { i in
                let on = i.id == value
                Button { value = i.id } label: {
                    VStack(spacing: 2) {
                        Icon(name: i.icon, size: 24)
                        Text(i.label).font(.td(11, .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(on ? Td.sunset : Td.ink2)
                    .background(Capsule().fill(on ? Td.verreMoyen : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Td.s2)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Td.verreMoyen))
        .overlay(Capsule().strokeBorder(Td.verreBord))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
    }
}

/// Toast d'info (Toast).
struct Toast: View {
    let title: String
    var detail: String?
    var icon: LucideIcon = .info
    var tint: Color = Td.ciel

    var body: some View {
        HStack(spacing: Td.s3) {
            Icon(name: icon, size: 22).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.td(15, .semibold))
                if let detail { Text(detail).font(.td(13)).foregroundStyle(Td.ink2) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Td.s3)
        .padding(.horizontal, Td.s4)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Color(hex: 0x26272E, alpha: 0.72)))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.verreBord))
    }
}

/// Interrupteur (Toggle) avec titre et aide.
struct TdToggle: View {
    let label: String
    var hint: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.td(17))
                if let hint { Text(hint).font(.td(13)).foregroundStyle(Td.ink3) }
            }
        }
        .tint(Td.sunset)
    }
}

/// État vide ou d'erreur centré (td-chart__state).
struct EmptyState: View {
    let icon: LucideIcon
    let text: String

    var body: some View {
        VStack(spacing: Td.s2) {
            Icon(name: icon, size: 24)
            Text(text).font(.td(15)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Td.ink3)
        .frame(maxWidth: .infinity)
        .padding(Td.s6)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
    }
}

/// Coins de visée du scanner (Rejoindre : 220, rayon 16, trois orange et un rose).
struct ScanCorners: View {
    var size: CGFloat = 220
    var arm: CGFloat = 40
    var radius: CGFloat = 16

    var body: some View {
        ZStack {
            corner(Td.sunset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            corner(Td.sunset).scaleEffect(x: -1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            corner(Td.sunset).scaleEffect(y: -1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            corner(Td.crepuscule).scaleEffect(x: -1, y: -1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func corner(_ c: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: arm))
            p.addLine(to: CGPoint(x: 2, y: radius + 2))
            p.addArc(tangent1End: CGPoint(x: 2, y: 2), tangent2End: CGPoint(x: radius + 2, y: 2), radius: radius)
            p.addLine(to: CGPoint(x: arm, y: 2))
        }
        .stroke(c, lineWidth: 4)
        .frame(width: arm, height: arm)
    }
}
