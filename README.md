# Juafem performance test

## To run JuAFEM performance test

* Change the settings in `JuAFEMPerformance.jl`.
* Run `julia --project` in this folder.
* Run `import Pkg; Pkg.instantiate()`
* Run `include("JuAFEMPerformance.jl")`
    - Run `run_experiment()` do run the experiment
    - Run `plot_results()` to plot results

## To run JuliaFEM performance test

* Run e.g. `julia --project JuliaFEMPerformance.jl TET10_220271 1x4
 
## Results 921k element model

### 4 threads

```
 ──────────────────────────────────────────────────────────────────────────────────────────────
                                                       Time                   Allocations
                                               ──────────────────────   ───────────────────────
               Tot / % measured:                     309s / 100%            84.1GiB / 100%

 Section                               ncalls     time   %tot     avg     alloc   %tot      avg
 ──────────────────────────────────────────────────────────────────────────────────────────────
 analysis                                   1     308s   100%    308s   84.1GiB  100%   84.1GiB
   timesteps                                2     222s  72.1%    111s   52.3GiB  62.2%  26.2GiB
     factorization backslash                2     168s  54.5%   83.9s   43.8GiB  52.0%  21.9GiB
     data output                            2    17.5s  5.68%   8.74s   2.73GiB  3.24%  1.36GiB
     apply boundary conditions              2    16.4s  5.34%   8.22s   5.66GiB  6.72%  2.83GiB
     assemble                               2    12.7s  4.13%   6.36s    146MiB  0.17%  72.8MiB
     post processing                        2    5.96s  1.94%   2.98s   22.1MiB  0.03%  11.1MiB
     update boundary conditions             2   67.4ms  0.02%  33.7ms   14.3MiB  0.02%  7.15MiB
   setup cost                               1    86.0s  27.9%   86.0s   31.8GiB  37.8%  31.8GiB
     find minimizing perm                   1    27.1s  8.80%   27.1s    752MiB  0.87%   752MiB
     reading input                          1    16.5s  5.35%   16.5s   3.80GiB  4.52%  3.80GiB
     create sparsity pattern                1    15.5s  5.04%   15.5s   18.1GiB  21.6%  18.1GiB
     create coloring mesh                   1    7.68s  2.49%   7.68s   2.13GiB  2.53%  2.13GiB
     converting input to JuAFEM mesh        1    6.47s  2.10%   6.47s    952MiB  1.10%   952MiB
     creating dofs                          1    583ms  0.19%   583ms    266MiB  0.31%   266MiB
 ──────────────────────────────────────────────────────────────────────────────────────────────
```
#### 1 thread

```
 ──────────────────────────────────────────────────────────────────────────────────────────────
                                                       Time                   Allocations
                                               ──────────────────────   ───────────────────────
               Tot / % measured:                     460s / 100%            84.1GiB / 100%

 Section                               ncalls     time   %tot     avg     alloc   %tot      avg
 ──────────────────────────────────────────────────────────────────────────────────────────────
 analysis                                   1     459s   100%    459s   84.1GiB  100%   84.1GiB
   timesteps                                2     375s  81.7%    187s   52.3GiB  62.2%  26.2GiB
     factorization backslash                2     294s  64.1%    147s   43.8GiB  52.0%  21.9GiB
     assemble                               2    32.0s  6.97%   16.0s    145MiB  0.17%  72.3MiB
     data output                            2    16.8s  3.66%   8.40s   2.73GiB  3.24%  1.36GiB
     post processing                        2    16.1s  3.52%   8.07s   22.3MiB  0.03%  11.1MiB
     apply boundary conditions              2    15.0s  3.26%   7.49s   5.66GiB  6.72%  2.83GiB
     update boundary conditions             2   64.7ms  0.01%  32.3ms   14.3MiB  0.02%  7.15MiB
   setup cost                               1    84.0s  18.3%   84.0s   31.8GiB  37.8%  31.8GiB
     find minimizing perm                   1    26.7s  5.83%   26.7s    752MiB  0.87%   752MiB
     reading input                          1    16.6s  3.62%   16.6s   3.80GiB  4.52%  3.80GiB
     create sparsity pattern                1    15.7s  3.43%   15.7s   18.1GiB  21.6%  18.1GiB
     create coloring mesh                   1    7.66s  1.67%   7.66s   2.13GiB  2.53%  2.13GiB
     converting input to JuAFEM mesh        1    6.37s  1.39%   6.37s    952MiB  1.10%   952MiB
     creating dofs                          1    596ms  0.13%   596ms    266MiB  0.31%   266MiB
 ──────────────────────────────────────────────────────────────────────────────────────────────
```

## Scaling

<img width="634" alt="screen shot 2018-09-26 at 20 05 03" src="https://user-images.githubusercontent.com/1282691/46115945-79becc00-c1c7-11e8-9b2c-990b40b364f4.png">

