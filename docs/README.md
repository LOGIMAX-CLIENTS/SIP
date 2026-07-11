# startGOLD — Developer Documentation

> **Welcome to the startGOLD mobile app documentation!**  
> If you're new to the project, start with the **Project Overview** and **Setup Guide**.

---

## 📚 Documentation Index

| # | Document | Description |
|---|----------|-------------|
| 01 | [Project Overview](./01_project_overview.md) | What startGOLD is, business purpose, tech stack, environments |
| 02 | [Folder Structure](./02_folder_structure.md) | Complete directory map with descriptions of every folder and file |
| 03 | [Architecture Guide](./03_architecture.md) | Design patterns, data flow, init flow, auth flow, session management |
| 04 | [Setup Guide](./04_setup_guide.md) | Clone, install, configure, build, and run the app |
| 05 | [Feature Guide](./05_features.md) | Feature-by-feature breakdown (all 21 features) |
| 06 | [Security Architecture](./06_security.md) | RSA encryption, SSL pinning, root detection, session security |
| 07 | [API Reference](./07_api_reference.md) | Endpoint catalog, request/response formats, error handling |
| 08 | [State Management](./08_state_management.md) | Riverpod providers, patterns, and rules |
| 09 | [UI & Theming](./09_ui_theming.md) | Design system, colors, fonts, responsive sizing, shared widgets |
| 10 | [Routing Guide](./10_routing.md) | All 45+ named routes, navigation patterns, argument requirements |
| 11 | [Coding Conventions](./11_coding_conventions.md) | Naming, style guide, Git workflow, common mistakes |
| 12 | [Troubleshooting](./12_troubleshooting.md) | Common issues, debugging tips, and where to get help |

---

## 🚀 Quick Start for New Developers

1. **Read** → [01 Project Overview](./01_project_overview.md) — Understand what the app does
2. **Setup** → [04 Setup Guide](./04_setup_guide.md) — Get the app running on your machine
3. **Explore** → [02 Folder Structure](./02_folder_structure.md) — Know where everything lives
4. **Understand** → [03 Architecture Guide](./03_architecture.md) — Learn the patterns
5. **Build** → [11 Coding Conventions](./11_coding_conventions.md) — Follow the rules
6. **Debug** → [12 Troubleshooting](./12_troubleshooting.md) — When things go wrong

---

## 🏗️ Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart ≥3.4.1) |
| State Management | Riverpod |
| HTTP Client | Dio with interceptors |
| Real-time | WebSocket |
| Security | RSA-OAEP-SHA256, SSL Pinning |
| Payments | Cashfree SDK |
| Push Notifications | Firebase Cloud Messaging |
| Local Auth | Biometric (Fingerprint/FaceID) |

---

*Last updated: June 2026*
