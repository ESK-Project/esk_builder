# ESK Builder Environment Variables

- bool: accept 1/0, y/n, yes/no, t/f, true/false, on/off
- int: number

| **Name**      | **Use**                                | **Type** |
| ------------- | -------------------------------------- | -------- |
| BUILD_TARGET  | Build target: `xaga` or `generic`      | string   |
| KSU           | Include KernelSU                       | bool     |
| SUSFS         | Include SUSFS                          | bool     |
| LXC           | Include LXC (`xaga` only)              | bool     |
| STOCK_CONFIG  | Spoof stock config                     | bool     |
| JOBS          | Make jobs                              | int      |
| RESET_SOURCES | Reset source directory (kernel, clang) | bool     |
| TG_NOTIFY     | Telegram notify                        | bool     |

## Targets

- `xaga` uses the xaga kernel source and builds one `boot.img`.
- `generic` uses the GKI source and builds `boot-raw.img`, `boot-gz.img`, and `boot-lz4.img`.
- `LXC` is only supported for `xaga`.
