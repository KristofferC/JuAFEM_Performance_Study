# Juafem performance test

## To run JuAFEM performance test

* Change the settings in `JuAFEMPerformance.jl`.
* Run `julia --project` in this folder.
* Run `import Pkg; Pkg.instantiate()`
* Run `include("JuAFEMPerformance.jl")`
    - Run `run_experiment()` do run the experiment
    - Run `plot_results()` to plot results

## To run JuliaFEM performance test

* Run e.g. `julia --project JuliaFEMPerformance.jl TET10_220271 1x4`
 
## Results 921k element model

### JuAFEM

Nonzeros in factorization (no reordering, reordering)

```
[ Info: Created factorization pattern, total number of nonzeros: 2_290_365_201
[ Info: Created factorization pattern, total number of nonzeros: 1_325_629_941
```

#### 4 threads

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

#### Scaling

<img width="634" alt="screen shot 2018-09-26 at 20 05 03" src="https://user-images.githubusercontent.com/1282691/46115945-79becc00-c1c7-11e8-9b2c-990b40b364f4.png">

### JuliaFEM 

```
[ Info: Created factorization pattern, total number of nonzeros: 2_384_888_674
[ Info: Created factorization pattern, total number of nonzeros: 1_337_180_813
```

#### 4 threads

```
 ──────────────────────────────────────────────────────────────────────────────────────────────────
                                                                         Time         Allocations
                                                                    ──────────────   ──────────────
                           Total measured:                                798s           175GiB

 Section                                                    ncalls     time   %tot     alloc   %tot
 ──────────────────────────────────────────────────────────────────────────────────────────────────
 run simulation 1                                                1     787s   100%    173GiB  100%
   timeloop                                                      1     727s  92.4%    164GiB  94.7%
     solution                                                    2     483s  61.4%   82.8GiB  47.7%
       factorize K                                               2     386s  49.1%   68.2GiB  39.3%
       update solution                                           2    41.3s  5.25%   1.69GiB  0.97%
       solve u                                                   2    18.7s  2.38%    422MiB  0.24%
       eliminate boundary conditions using penalty method        2    13.2s  1.68%    833MiB  0.47%
       create symmetric K                                        2    11.1s  1.41%   11.3GiB  6.52%
       solve la                                                  2    9.40s  1.19%    388MiB  0.22%
     assemble                                                    2     234s  29.8%   80.8GiB  46.6%
       assemble problems                                         2     147s  18.7%   31.4GiB  18.1%
       construct global assemblies                               2    87.0s  11.1%   49.4GiB  28.5%
         get_field_assembly                                      2    63.5s  8.07%   37.3GiB  21.5%
         sum K                                                   2    17.4s  2.22%   11.3GiB  6.52%
         get_boundary_assembly                                   2    5.37s  0.68%    735MiB  0.41%
         sum f                                                   2    673ms  0.09%    141MiB  0.08%
   write results to disk                                         1    31.5s  4.01%   3.14GiB  1.81%
   initialize model                                              1    24.2s  3.07%   6.05GiB  3.49%
     parse input data                                            1    18.6s  2.36%   3.98GiB  2.29%
     initialize models                                           1    5.55s  0.71%   2.07GiB  1.19%
 ──────────────────────────────────────────────────────────────────────────────────────────────────
```

## Results 220k model

### JuAFEM

#### 4 threads 10 timesteps

```
 ──────────────────────────────────────────────────────────────────────────────────────────────
                                                       Time                   Allocations
                                               ──────────────────────   ───────────────────────
               Tot / % measured:                     255s / 100%            95.4GiB / 100%

 Section                               ncalls     time   %tot     avg     alloc   %tot      avg
 ──────────────────────────────────────────────────────────────────────────────────────────────
 analysis                                   1     254s   100%    254s   95.4GiB  100%   95.4GiB
   timesteps                               10     231s  91.1%   23.1s   88.2GiB  92.5%  8.82GiB
     factorization backslash               10     164s  64.5%   16.4s   78.5GiB  82.3%  7.85GiB
     apply boundary conditions             10    27.2s  10.7%   2.72s   6.59GiB  6.90%   674MiB
     data output                           10    21.9s  8.64%   2.19s   2.94GiB  3.08%   301MiB
     assemble                              10    15.1s  5.95%   1.51s    143MiB  0.15%  14.3MiB
     post processing                       10    2.14s  0.84%   214ms   20.6MiB  0.02%  2.06MiB
     update boundary conditions            10   60.2ms  0.02%  6.02ms   6.15MiB  0.01%   630KiB
   setup cost                               1    22.5s  8.86%   22.5s   7.17GiB  7.52%  7.17GiB
     find minimizing perm                   1    6.11s  2.41%   6.11s    177MiB  0.18%   177MiB
     create sparsity pattern                1    4.81s  1.90%   4.81s   4.03GiB  4.22%  4.03GiB
     reading input                          1    4.73s  1.86%   4.73s   0.96GiB  1.01%  0.96GiB
     create coloring mesh                   1    2.23s  0.88%   2.23s    388MiB  0.40%   388MiB
     converting input to JuAFEM mesh        1    1.53s  0.60%   1.53s    251MiB  0.26%   251MiB
     creating dofs                          1    220ms  0.09%   220ms   64.2MiB  0.07%  64.2MiB
 ──────────────────────────────────────────────────────────────────────────────────────────────
```

### JuliaFEM

#### 4 threads 10 timesteps

```
 ──────────────────────────────────────────────────────────────────────────────────────────────────
                                                                         Time         Allocations
                                                                    ──────────────   ──────────────
                           Total measured:                                523s           206GiB

 Section                                                    ncalls     time   %tot     alloc   %tot
 ──────────────────────────────────────────────────────────────────────────────────────────────────
 run simulation 1                                                1     512s   100%    204GiB  100%
   timeloop                                                      1     493s  96.4%    201GiB  98.8%
     solution                                                   10     272s  53.1%    126GiB  62.0%
       factorize K                                              10     190s  37.1%   57.4GiB  28.2%
       create symmetric K                                       10    14.0s  2.73%   13.2GiB  6.46%
       update solution                                          10    11.4s  2.24%   1.93GiB  0.95%
       solve u                                                  10    6.93s  1.35%    561MiB  0.27%
       solve la                                                 10    3.42s  0.67%    469MiB  0.22%
       eliminate boundary conditions using penalty method       10    1.08s  0.21%   0.98GiB  0.48%
     assemble                                                   10     211s  41.2%   74.2GiB  36.4%
       assemble problems                                        10     135s  26.4%   18.6GiB  9.15%
       construct global assemblies                              10    75.8s  14.8%   55.6GiB  27.3%
         get_field_assembly                                     10    65.2s  12.7%   41.4GiB  20.3%
         sum K                                                  10    9.90s  1.93%   13.2GiB  6.46%
         get_boundary_assembly                                  10    647ms  0.13%    889MiB  0.43%
         sum f                                                  10   73.4ms  0.01%    195MiB  0.09%
   initialize model                                              1    8.07s  1.58%   1.54GiB  0.76%
     parse input data                                            1    5.19s  1.01%   1.03GiB  0.50%
     initialize models                                           1    2.88s  0.56%    527MiB  0.25%
   write results to disk                                         1    6.43s  1.26%    878MiB  0.42%
 ──────────────────────────────────────────────────────────────────────────────────────────────────k
```

 With reoredering

```
 ──────────────────────────────────────────────────────────────────────────────────────────────────
                                                                         Time         Allocations
                                                                    ──────────────   ──────────────
                           Total measured:                                445s           175GiB

 Section                                                    ncalls     time   %tot     alloc   %tot
 ──────────────────────────────────────────────────────────────────────────────────────────────────
 run simulation 1                                                1     433s   100%    173GiB  100%
   timeloop                                                      1     413s  95.4%    171GiB  98.6%
     assemble                                                   10     213s  49.1%   74.2GiB  42.9%
       assemble problems                                        10     136s  31.5%   18.7GiB  10.8%
       construct global assemblies                              10    76.5s  17.6%   55.6GiB  32.1%
         get_field_assembly                                     10    66.0s  15.2%   41.4GiB  23.9%
         sum K                                                  10    9.79s  2.26%   13.2GiB  7.60%
         get_boundary_assembly                                  10    610ms  0.14%    889MiB  0.50%
         sum f                                                  10   73.3ms  0.02%    195MiB  0.11%
     solution                                                   10     190s  43.8%   95.8GiB  55.3%
       factorize K                                              10     119s  27.5%   42.9GiB  24.8%
       create symmetric K                                       10    14.0s  3.24%   13.2GiB  7.60%
       solve u                                                  10    10.9s  2.52%    561MiB  0.32%
       update solution                                          10    10.3s  2.38%   1.93GiB  1.12%
       solve la                                                 10    2.35s  0.54%    469MiB  0.26%
       eliminate boundary conditions using penalty method       10    1.10s  0.25%   0.98GiB  0.57%
   initialize model                                              1    8.62s  1.99%   1.54GiB  0.89%
     parse input data                                            1    5.55s  1.28%   1.03GiB  0.59%
     initialize models                                           1    3.07s  0.71%    527MiB  0.30%
   write results to disk                                         1    7.01s  1.62%    878MiB  0.50%
 ──────────────────────────────────────────────────────────────────────────────────────────────────k
 ```
