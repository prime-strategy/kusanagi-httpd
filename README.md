# kusanagi-httpd

Apache HTTP Server( for KUSANAGI Runs on Docker )

# Versions (tags)

- 2.4.68-r5

# Image Content

- Alpine:3.24.1
- httpd-2.4.68

# Architectures

`linux/amd64`, `linux/386`, `linux/arm64/v8`, `linux/arm/v6`, `linux/arm/v7`,
`linux/riscv64`

`mod_lua` runs on LuaJIT everywhere except `linux/riscv64`, which uses stock
Lua 5.3 -- LuaJIT has no RISC-V port, so Alpine ships no `luajit` package there.

# Release

Images are built and pushed to Docker Hub by GitHub Actions
(`.github/workflows/docker-publish.yml`), not by Docker Hub Automated Builds.

Pushing a git tag of the form `X.Y.Z-rN` publishes `primestrategy/kusanagi-httpd:X.Y.Z-rN`:

```
git tag 2.4.68-r6 && git push origin 2.4.68-r6
```

`workflow_dispatch` runs the same build; leave the `tag` input empty for a
build-only dry run, or set it to re-publish a tag.

Each architecture is built on its own runner, scanned with trivy, and pushed by
digest; a final job assembles the manifest list. A trivy finding on any
architecture fails that job, and the manifest list is never created, so no tag
ever points at an unscanned or vulnerable image. Expect `linux/riscv64`, the one
fully emulated target, to dominate the wall-clock time.

Requires repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

