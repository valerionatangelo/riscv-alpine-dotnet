This repository is used to locally reproduce the .NET RISC-V build flow described in build.yml, then turn the resulting linux-musl-riscv64 SDK tarball into a reusable Alpine riscv64 Docker image with a working dotnet installation.



Primary goal:

Build a linux-musl-riscv64 .NET SDK tarball locally, then build and validate an Alpine riscv64 image containing that SDK, with dotnet available in PATH.



Important context:



build.yml is the reference workflow and should be read first.

The preferred target is linux-musl-riscv64, not glibc, because the final runtime image is Alpine-based.

The workflow should be reproduced locally rather than through GitHub Actions.

The result should be reusable and scripted, not a one-off manual sequence.

Prefer PowerShell plus Docker Desktop on Windows as the primary local workflow.

Prefer Docker Buildx through Docker Desktop for cross-platform image builds and tests.

Avoid requiring a native RISC-V machine unless strictly necessary.



Expected outputs:



A PowerShell script to clone the upstream dotnet repo for a chosen fork and branch

A PowerShell script to apply the same patch logic used in build.yml when needed

A PowerShell script to run the local SDK build for linux-musl-riscv64

A PowerShell script to locate the generated dotnet-sdk-\*-linux-musl-riscv64.tar.gz

A Dockerfile that builds an Alpine riscv64 image with the SDK extracted into /opt/dotnet

A PowerShell script to build the Docker image with buildx for linux/riscv64

A PowerShell script to validate the image by running dotnet --info and uname -m

A short notes file documenting how to rerun the workflow



Implementation rules:



Follow build.yml closely unless there is a good local-only reason not to.

Prefer simple, reusable PowerShell scripts over ad hoc commands.

Keep variables configurable: fork, branch, branding, artifact path, image name, image tag.

Keep all generated files organized under the current workspace.

Use Docker Desktop and Docker Buildx where needed.

If something cannot be fully executed in the current environment, still leave complete scripts and explain what remains.



PowerShell and Docker Desktop guidance:



Prefer PowerShell over bash unless there is a strong reason not to.

Assume Docker Desktop is installed and configured with Linux containers.

Prefer Docker Desktop’s built-in Buildx and emulation support instead of manual QEMU setup when possible.

Scripts should be easy to run from a normal PowerShell prompt on Windows.

Avoid unnecessary WSL-specific assumptions unless required.



Alpine image requirements:



Base image must be Alpine

Target platform must be linux/riscv64

Install any minimal native dependencies required for .NET

Extract the SDK tarball into /opt/dotnet

Set DOTNET\_ROOT=/opt/dotnet

Add /opt/dotnet to PATH

Ensure dotnet --info works in the container



Validation requirements:

At minimum, validate:



uname -m

dotnet --info



Preferred working style:



Inspect build.yml

Summarize the plan briefly

Implement scripts and Dockerfile

Run the build where feasible

Build and test the final Alpine image

Clearly report any incomplete steps



Practical constraints:



Avoid unnecessary complexity

Favor reproducibility over cleverness

Do not change the goal from SDK-on-Alpine-riscv64

