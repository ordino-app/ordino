# Contributing

Thanks for helping. Bug reports and pull requests are welcome.

## Licence of contributions

By submitting a contribution you agree that it is licensed under the project's
[MIT License](LICENSE) ("inbound = outbound"), and you certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): you wrote it,
or have the right to submit it under that licence.

Sign each commit off to say so:

    git commit -s -m "fix: ..."

## Workflow

- Branch from `main`, use [Conventional Commits](https://www.conventionalcommits.org/).
- `make lint test` must pass; CI checks every pull request.
- Keep the app free of tracking: no analytics, no network calls besides the update check.
