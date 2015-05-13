kvmadm 0.9.0-rc5
============
Manage KVM instances under SMF control

[![Build Status](https://travis-ci.org/hadfl/kvmadm.svg?branch=master)](https://travis-ci.org/hadfl/kvmadm)
[![Coverage Status](https://img.shields.io/coveralls/hadfl/kvmadm.svg)](https://coveralls.io/r/hadfl/kvmadm?branch=master)

Kvmadm takes care of setting up kvm instances on illumos derived operating
systems with SMF support.  The kvm hosts run under smf control.  Each host
will show up as a separate SMF service instance. Kvmadm supports KVM instances
set-up as SMF service instance within individual zones.

Upgrading from a pre 0.9.0 version
----------------------------------

It is recommended to shut down all KVM instances before upgrading. Run pathes changed (i.e. each
instance gets its own subdirectory) to prevent inter-zone monitor access. 
You will need to shut down your KVMs manually once if you upgrade from a pre 0.9.0 version while KVM instances are running.

Setup
-----

Kvmadm uses only core perl, so it should install out of the box on any machine with a current perl installation.
It is advised to install kvmadm into a separate directory as the base directory of kvmadm will be mounted in the zones.

```sh
wget https://github.com/hadfl/kvmadm/releases/download/v0.9.0-rc5/kvmadm-0.9.0-rc5.tar.gz
tar zxvf kvmadm-0.9.0-rc5.tar.gz
cd kvmadm-0.9.0-rc5
./configure --prefix=/opt/kvmadm-0.9.0-rc5 
```

Now you can run

```sh
make install
```

By default this will also install the kvmadm smf manifest in
```/var/svc/manifest/site``` you can disable this behavior by calling
configure with ```--disable-svcimport``` 

Check the [man page](doc/kvmadm.pod) for information about how to use kvmadm.

Support and Contributions
-------------------------
If you find a problem with kvmadm, please open an Issue on GitHub.

And if you have a contribution, please send a pull request.

Enjoy!

Dominik Hassler & Tobi Oetiker
2015-05-05
