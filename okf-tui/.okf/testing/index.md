# Testing

How a full-screen terminal app is proven, and what each layer can and cannot
catch.

* [Testing Frames Without a Terminal](headless-frames.md) - Driving real interactions headlessly, and the discipline of proving a check can fail.
* [The One Test That Opens a Terminal](pty-test.md) - The single pty walk, and the three timing traps that made it flake on the floor.
* [The CI Matrix and What Only It Catches](ci-matrix.md) - Ten Rubies, the Docker floor check, and the dependency bug a local run cannot see.
