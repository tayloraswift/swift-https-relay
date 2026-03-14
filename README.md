## usage

```
https-relay \
    <target domain>:<target port>@<public port> \
    <target domain>:<target port>@<public port>:<path to ssl certificate>
```

## examples

### allow SSH into an internal node, via port `2020` on a public node

this requires the public node to be able to resolve `db.rarestype.com` to something it can access

```
CNAME db.rarestype.com → ip-172-xxx-xxx-xxx.ec2.internal
```

```
https-relay db.rarestype.com:22@2020
```

### securely expose an HTTP server to the public internet via HTTPS

for instance, if you have a web server or backend service running locally that doesn't have built-in support for SSL/TLS, you can put this relay in front of it. the relay will bind to a public-facing port, handle the SSL certificates to provide a secure HTTPS connection for external users, and safely pass the unencrypted requests down to your internal service.

```
https-relay ui.rarestype.com:8443@8443:/etc/letsencrypt/live/ui.rarestype.com
```
