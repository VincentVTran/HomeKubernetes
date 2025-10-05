### Documentation
https://github.com/dragonflydb/dragonfly-operator

###
To run redis-CLI:
```
kubectl run -it --rm --restart=Never redis-cli --image=redis:7.0.10 -- redis-cli -h dragonfly-instance.dragonfly-operator-system
```
Then run Shift+R