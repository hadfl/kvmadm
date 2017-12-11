kvmadm 0.12.2
============
Manage KVM instances under SMF control

[![Build Status](https://travis-ci.org/hadfl/kvmadm.svg?branch=master)](https://travis-ci.org/hadfl/kvmadm)
[![Coverage Status](https://img.shields.io/coveralls/hadfl/kvmadm.svg)](https://coveralls.io/r/hadfl/kvmadm?branch=master)

`kvmadm` takes care of setting up kvm instances on illumos derived operating
systems with SMF support. The kvm hosts run under smf control. Each host
will show up as a separate SMF service instance. `kvmadm` supports KVM instances
set-up as SMF service instance within individual zones.

Setup
-----

`kvmadm` uses only core perl, so it should install out of the box on any machine with a current perl installation.
It is advised to install kvmadm into a separate directory as the base directory of `kvmadm` will be mounted in the zones.

```sh
wget https://github.com/hadfl/kvmadm/releases/download/v0.12.2/kvmadm-0.12.2.tar.gz
tar zxvf kvmadm-0.12.2.tar.gz
cd kvmadm-0.12.2
./configure --prefix=/opt/kvmadm-0.12.2 
```

Now you can run

```sh
gmake
gmake install
```

You can import make configure install a `kvmadm`
service manifest by calling configure with the option
`--enable-svcinstall=/var/svc/manifest/site`.

Check the [man page](doc/kvmadm.pod) for information about how to use `kvmadm`.

Support and Contributions
-------------------------
If you find a problem with `kvmadm`, please open an Issue on GitHub.

And if you have a contribution, please send a pull request.

Enjoy!

Dominik Hassler & Tobi Oetiker
2017-12-11
