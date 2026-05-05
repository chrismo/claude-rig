## TLS x509 failures usually mean sandbox, not the network

If a network command fails with `x509` / certificate trust errors (e.g. `OSStatus -26276` from `gh`, curl SSL trust errors), and you're in auto-approve sandbox mode, ask to retry outside the sandbox before debugging certs, keychain, or proxy. It's almost always the sandbox blocking the system trust store.
