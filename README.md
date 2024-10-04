# Curie

[![Build Status](https://github.com/macvmio/curie/actions/workflows/main.yml/badge.svg)](https://github.com/macvmio/curie/actions/workflows/main.yml)

## Overview

*Curie* is a lightweight, open-source virtualization solution, leveraging the Apple [Virtualization.framework](https://developer.apple.com/documentation/virtualization).

It allows users to run and manage isolated environments, making it easier to develop and test software in a controlled environment.

### Key Features

* **Containerization**: Like Docker, the tool allows users to create and manage containers, each providing a separate environment for running applications. Containers share the macOS kernel but maintain their own filesystem and resource constraints.

* **Resource Management**: The tool offers basic resource management options, allowing users to allocate CPU and memory resources to containers. This ensures that containers run efficiently without overloading the host system.

* **Image Management**: Users can create, modify, abd clone images. Images can be stored locally and reused across multiple  containers.

## Usage

### Commands

#### Download an image restore file

```sh
curie download -p ~/Downloads/RestoreImage.ipsw
```

#### Build an image

```sh
curie build myteam/myimage/test-image:1.0 -i ~/Downloads/RestoreImage.ipsw -d "60 GB" 
```

#### Remove an image

```sh
curie rmi myteam/myimage/test-image:1.0
```

#### List images

```sh
curie images

# Example output

REPOSITORY                 TAG     IMAGE ID         CREATED         SIZE
myteam/myimage/ci/test     2.3     9bf95fe0f7f0     2 hours ago     60.03 GB
myteam/myimage/ci/test     2.1     7d5347edc7ca     7 hours ago     60.03 GB
```

The command has also `--format` (`-f`) parameter which allows to output JSON.

```sh
curie images -f json
```

Example output:
```json
[
  {
    "created" : "36 minutes ago",
    "image_id" : "a5abe5c92583",
    "repository" : "myteam\/myimage\/ci\/test",
    "size" : "60.03 GB",
    "tag" : "2.4"
  },
  {
    "created" : "4 days ago",
    "image_id" : "4b72a86471ef",
    "repository" : "myteam\/myimage\/ci\/test",
    "size" : "60.03 GB",
    "tag" : "2.3"
  },
  {
    "created" : "1 week ago",
    "image_id" : "7d5347edc7ca",
    "repository" : "myteam\/myimage\/ci\/test",
    "size" : "60.03 GB",
    "tag" : "2.1"
  }
]
```

#### Clone an image

```sh
curie clone myteam/myimage/test-image:1.0 myteam/myimage/test-image:1.1
```

#### Export an image

```sh
curie export a8302cc3e913 -p test-image-2.4.zip -c

# or without compression
curie export a8302cc3e913 -p test-image-2.4
```

#### Import an image

```sh
curie import myteam/myimage/test-image:2.4 -p test-image-2.4.zip
```

#### Start an ephemeral container

The container will be deleted after it is closed.

```sh
curie run myteam/myimage/test-image:1.0
```

#### Create a container

```sh
curie create myteam/myimage/test-image:1.0
```

#### List containers

```sh
curie ps

# Example output

CONTAINER ID     REPOSITORY                               TAG     CREATED           SIZE
7984867efb71     @7984867efb71/myteam/myimage/ci/test     2.1     3 minutes ago     60.03 GB
```

The command has also `--format` (`-f`) parameter which allows to output JSON.

#### Start a container

All changes that are made in the container will be applied to the image once the container is closed.

```sh
curie start @7984867efb71/myteam/myimage/ci/test
```

#### Inspect an image or a container

```sh
curie inspect myteam/myimage/ci/test:2.3

# Example output

Metadata:
  id: 9bf95fe0f7f0
  name: <none>
  createdAt: 2023-09-17T18:22:58Z
  network:
    devices:
      index: 0
      macAddress: 11:37:c4:2f:2a:a7

Config:
  name: test:2.3
  cpuCount: 8
  memorySize: 8.00 GB
  display:
    width: 1920px
    height: 1080px
    pixelsPerInch: 144
  network:
    devices:
      index: 0
      macAddress: synthesized
      mode: NAT
```

Inspect command supports `--format` (`-f`) parameter.

#### Edit config of an image or a container

The command will open the config file in the default text editor.

```sh
curie config myteam/myimage/ci/test:2.3
```

### Config file

`create` command allows to pass path to config file (`-c, --config-path <config-path>`). Config file describes basic properties of the virtual machine such as number of CPUs, RAM etc.

Example:

```json
{
  "cpuCount" : 8,
  "network" : {
    "devices" : [
      {
        "mode" : "NAT",
        "macAddress" : "synthesized"
      }
    ]
  },
  "display" : {
    "width" : 1920,
    "height" : 1080,
    "pixelsPerInch" : 144
  },
  "sharedDirectory": {
    "directories": [
      {
        "currentWorkingDirectory": {
          "options": {
            "name": "cwd",
            "readOnly": false
          }
        }
      }
    ]
  },
  "name" : "Test VM",
  "memorySize" : "8 GB"
}
```

### CPU count

Possible values:
* `<count>`, e.g. `8` - hardcoded number of CPUs
* `"minimumAllowedCPUCount"` - minimum number of CPUs
* `"maximumAllowedCPUCount"` - maximum number of CPUs

### Memory size

Possible values:
* `"<number> GB"`, e.g. `"80 GB"` - hardcoded size (user-friendly format)
* `"minimumAllowedMemorySize"` - minimum size
* `"maximumAllowedMemorySize"` - maximum size

### Display

Properties:
* `width` - width of the screen
* `height` - height of the screen
* `pixelsPerInch` - density

### Network

Currently we only support `NAT` interfaces. Each interface can have MAC address assigned in the following way:
* `"automatic"` - Virtualization Framework will transparently assign new MAC address
* `"synthesized"` - Curie will automatically generate unique MAC address per `run` or `start` operation (both MAC and IP address can be found using `curie inspect` command)
* e.g. `"6e:7e:67:0c:93:65"` - manual MAC address

### Shared directories

#### Share current working directory

Use `-s, --share-cwd` to share current working directory with the guest OS.

#### Share an arbitrary directory

Add the directory descriptor to `config.json`, e.g.

```json
{
 "sharedDirectory" : {
    "directories" : [
      {
        "directory": {
          "options": {
            "path": "/Users/marcin/shared-directory",
            "name": "shared-directory",
            "readOnly": false
          }
        }
      }
    ],
    "automount" : true
  }
}
```

#### Mount shared directories

A shared directory is automatically mounted via `/Volumes/My Shared Files` unless "automount" is disable via `config.json`, e.g.

```json
{
  "sharedDirectory" : {
    "directories" : [],
    "automount" : false
  }
}
```

If `automount` is set to `false`, the volume `curie` will need to be mounted manually, e.g.

```sh
# mounting shared directory
mkdir -p shared # you can pick up different name
mount -t virtiofs curie shared

# or
mkdir -p shared
mount_virtiofs curie shared
```

### Data location

By default, curie stores images and containers in `~/.curie` directory. You can change the location by setting `CURIE_DATA_ROOT` environment variable.

## Development

### Requirements

- Xcode 14.2 or newer

### Build

Execute the commands below to build the project in debug mode.

```sh
make build 
make sign
```

### Run

Execute the commands below to run the project locally.

```sh
.build/debug/curie --help
```

## Attributions

We would like to thank the authors and contributors of the following projects:

- [Virtualization.framework](https://developer.apple.com/documentation/virtualization)
- [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- [swift-tools-support-core](https://github.com/apple/swift-tools-support-core)
- [SwiftLint](https://github.com/realm/SwiftLint)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)

## License

Curie is released under version 2.0 of the [Apache License](LICENSE.txt).
