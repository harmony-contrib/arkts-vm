# ArkTS-VM

This project provide an out of box executable binary to run `abc` file.

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

| Name           | Type    | Default   | Description                                      |
| -------------- | ------- | --------- | ------------------------------------------------ |
| tag            | String  | 6.0.0     | Release tag，从 arkts-vm releases 下载           |
| cache          | Boolean | true      | 是否使用 GitHub Actions cache 缓存安装目录       |
| skip-download  | Boolean | false     | 跳过下载，使用已有的 $HOME/setup-arkvm 下压缩包   |

### Outputs

| Name       | Description                    |
| ---------- | ------------------------------ |
| arkvm-path | 安装根目录（如 $HOME/setup-arkvm/arkvm） |
| platform   | linux-x64 或 macos-arm64        |

### Support Platforms

- x86_64 Linux (gnu)
- aarch64 macOS (Apple Silicon)

