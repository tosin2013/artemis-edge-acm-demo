## Related Issue

Closes #<!-- issue number -->

## Description

<!-- What does this PR do? Why is it needed? -->

## Changes

- 

## Checklist

- [ ] `helm lint .` passes
- [ ] `helm template . --values values.yaml` renders cleanly
- [ ] `shellcheck scripts/*.sh bootstrap.sh` passes (if scripts changed)
- [ ] `yamllint -d relaxed` passes on modified YAML files
- [ ] Mode 2 overlays still render: `helm template . -f values.yaml -f values-mode2.yaml`
- [ ] Related issue is linked above
- [ ] Documentation updated (if applicable)

## Testing

<!-- How was this tested? -->
