# ArkTS-VM

This project provides an out-of-the-box executable binary to run `abc` files.

## GitHub Action (setup-arkvm)

### Example

```yaml
- name: Setup arkvm
  uses: harmony-contrib/arkts-vm@v1.0.0
  with:
    tag: 6.0.0
    cache: true
```

### Inputs

| Name          | Type    | Default | Description                                                 |
| ------------- | ------- | ------- | ----------------------------------------------------------- |
| tag           | String  | 6.0.0   | Release tag to download from arkts-vm releases              |
| cache         | Boolean | true    | Use GitHub Actions cache for the installation directory     |
| skip-download | Boolean | false   | Skip download; use existing archive under $HOME/setup-arkvm |

### Outputs

| Name       | Description                                      |
| ---------- | ------------------------------------------------ |
| arkvm-path | Installation root (e.g. $HOME/setup-arkvm/arkvm) |
| platform   | linux-x64 or macos-arm64                         |

### Supported Platforms

- x86_64 Linux (gnu)
- aarch64 macOS (Apple Silicon)
