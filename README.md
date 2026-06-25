# argo-gitops — Bridge (Management) Cluster GitOps

GitOps source of truth for the **bridge / management cluster** — the cluster the
Armada Bridge installer builds and runs on. This is **separate** from
`armadasystems/bridge-cluster-recipes`, which is the catalog/recipes for
**tenant / target** clusters.

| Plane | Repo | What it deploys |
|-------|------|-----------------|
| Tenant clusters | `bridge-cluster-recipes` (catalog + recipes) | Workloads onto Kamaji/CAPI tenant clusters via `environment-manager` |
| **Bridge cluster (this repo)** | `argo-gitops` | The bridge cluster's own platform components (MetalLB, …) |

## How it runs

```
argo-gitops (this repo, GitHub)
   │  installer clones at install time, renders per-install values,
   │  and seeds into in-cluster Gitea  →  platform/bridge-gitops
   ▼
Gitea: platform/bridge-gitops          (runtime mirror — air-gap safe)
   ▼  ArgoCD root Application "bridge-root"  (destination: in-cluster)
   ▼
Bridge cluster workloads               (metallb-system, …)
```

ArgoCD pulls from the **Gitea mirror**, never from GitHub directly, so cluster
sync needs no outbound internet. (Pointing ArgoCD straight at GitHub is fine as a
dev-only shortcut.)

The installer should **pin** this repo to a branch/tag per release to avoid version
skew (same pattern as `platform_catalog_source_branch` for the catalog).

## Layout

```
argo-gitops/
├── bootstrap/
│   └── bridge-root.yaml        # App-of-Apps. Applied once after ArgoCD is up.
├── apps/                       # one ArgoCD Application per component (watched by bridge-root)
│   └── metallb.yaml            # MetalLB chart, multi-source (sync-wave 1)
└── values/                     # Helm values files, referenced by apps/* via the $values ref
    └── metallb.yaml
```

> `apps/` is scanned by `bridge-root` as manifests to apply (`recurse: false`), so
> values files must live **outside** it — hence the top-level `values/` dir.
> Component Applications use a **multi-source** spec to combine a remote Helm chart
> with a values file from this repo (`valueFiles: [$values/values/<name>.yaml]`).

> The MetalLB `IPAddressPool` / `L2Advertisement` (runtime `cluster_lb_ip`) is
> intentionally **not** managed here yet — it stays in Ansible (installer Task 19)
> for now. Add it later under `cluster-config/` with a seed-time-rendered IP if/when
> we want it in GitOps.

## Per-install runtime values

Some values are known only at install time. The installer substitutes placeholders
at **seed time**, before pushing to Gitea:

| Placeholder | Source | Where |
|-------------|--------|-------|
| `__GITOPS_REPO_URL__` | Gitea bridge-gitops URL | `bootstrap/bridge-root.yaml` |

Default `__GITOPS_REPO_URL__` for production is the in-cluster Gitea mirror:
`http://gitea-http.gitea.svc.cluster.local:3000/platform/bridge-gitops.git`

## Adding a component (migration recipe)

1. Convert the installer's Jinja2 Helm values → static YAML in a new `apps/<name>.yaml`.
2. Move any secret out of values → `existingSecret` seeded by Ansible (ESO/Vault later).
3. If it has runtime-valued config, add a manifest under `cluster-config/` + an
   `apps/<name>-config.yaml` Application, with a placeholder seeded by the installer.
4. Gate the corresponding Ansible task behind `manage_<name>_via_gitops` so the two
   systems never co-own the component.
5. Test in lab, then promote.

See `bridge-installer/docs/gitops-management-cluster-migration-design.md` for the
full design and rationale.
