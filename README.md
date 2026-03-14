## usage

```
https-relay \
    <target domain>:<target port>@<public port> \
    <target domain>:<target port>@<public port>:<path to ssl certificate>
```

## examples

allow SSH into an internal node, via port `2020` on a public node. 

```
https-relay db.rarestype.com:22@2020
```
