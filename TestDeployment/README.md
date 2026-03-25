## Useful K8 Commands
### Log into pod
`kubectl exec -it <pod name> -n test -- /bin/bash`

### View cilium gateway
`kubectl -n kube-system exec -it ds/cilium -- cilium monitor`

### View Pods Memory Useage
`kubectl top pods`

### View Node Memory Useage
`kubectl top nodes`

## Useful Linux Commands

### Install ps, lsof, ping, etc.
```
apt update
apt install procps iproute2 net-tools iputils-ping netcat traceroute lsof
```

### Process
#### Log into pod
`ps aux` - a = List of processes for all users, u = user oriented format, x = processes that are not attached to controlling terminal

or 
`ps aux | grep containerd` 

#### To list open sockets (which ports and process) 
`lsof -i` - i = IPv4 or IPv6

### Show all associated files for a process (very useful)
`lsof -p <PID>`

Note:
- CWD = Current Working Directory for the process
- RTD = Root directory for the process
- TXT = Text segment of the executable
- MEM = Shared libraries that are loaded into address space (AKA import)

### Network
#### Test TCP connectivity
`nc -vz <pod-ip> <port> # netcat: checks TCP connect` 
or
`curl http://<pod-ip>:<port>`

#### Trace TCP route
`sudo traceroute -T -p 443 10.43.0.1` 

### #Test UDP connectivity
`nc -vu <pod-ip> <port>` 

### Memory
#### To view CPU/memory utilization (Top user display)
`top -p`
#### To view swap memory (Disk memory used when RAM is full or to free up RAM for more active pages)
`free -m` or `swapon -s`

## Useful Containerd Commands
### To view all containers on a given node
`sudo crictl ps -a`


## Useful Celium (CNI) Command
### To view CNI routing
`kubectl -n kube-system exec -it ds/cilium -- cilium monitor`