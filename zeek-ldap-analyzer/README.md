1. build the Docker images:

```
$ docker build -f ./zeek-gcc.Dockerfile -t zeek-gcc:3.0.12 .
...
Successfully tagged zeek-gcc:3.0.12

$ docker build -f ./zeek-llvm.Dockerfile -t zeek-llvm:3.0.12 .
...
Successfully tagged zeek-llvm:3.0.12
```

2. make a place for the logs

```
$ mkdir -p ./logs-llvm ./logs-gcc && rm -f ./logs-llvm/* ./logs-gcc/*
```

3. run the tests

```
$ docker run --rm -v "$(pwd)"/logs-llvm:/logs:rw zeek-llvm:3.0.12
WARNING: No Site::local_nets have been defined.  It's usually a good idea to define your local networks.

$ ls -l ./logs-llvm/ldap.log
ls: cannot access './logs-llvm/ldap.log': No such file or directory

$ docker run --rm -v "$(pwd)"/logs-gcc:/logs:rw zeek-gcc:3.0.12 
WARNING: No Site::local_nets have been defined.  It's usually a good idea to define your local networks.

$ ls -l ./logs-gcc/ldap.log 
-rw-r--r-- 1 user user 14,278 Jan 26 16:03 ./logs-gcc/ldap.log
```
