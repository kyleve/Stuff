# Replay of 100 merged PRs

For each PR, the table estimates the difference between a full native run and a selected run on the same four active workers. Positive values mean credits or seconds saved. The calculation uses the #555 full run. The two #554 runs provide separate timing estimates. [Worker inputs and calculation](worker-inputs.md)

The sample runs from #414 on October 22 through #555 on November 22, 2026 UTC, in descending merge order. Each row uses the landed commit and its first parent. From a clean checkout of `327b3f58e`, substitute the row's commit in the following command to replay its bundle selection with the same graph. The two arguments exclude local edits. [Selector experiment](../2026-11-21-affected-test-selection/RESULTS.md)

```sh
./test --dry-run --json --base "${commit}^1" --head "$commit"
```

“Bundles” gives selected ordinary/image counts out of 22/6. “Docs skip” means the existing PR policy already skips native validation. “Full fallback” means the selector requested all 28 bundles. The selected rows use the exact bundle sets below. “Last worker” identifies the last worker to finish in the selected native gate. Snapshot 0 finished last in the measured full run. “Fixture inputs unchanged” marks a potential warm installer-site fixture cache hit under the audited file policy. Rows display tenths, and totals use the underlying values.

| PR | Landed commit | Selection | Bundles | Unit credits | Snapshot 0 credits | Snapshot 1 credits | Snapshot 2 credits | Native gate s | Snapshot gate s | Last worker | Fixture inputs unchanged |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [#555](https://github.com/kyleve/Stuff/pull/555) | [327b3f58e](https://github.com/kyleve/Stuff/commit/327b3f58e6896ce72a037aef0462187ff78e711b) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#554](https://github.com/kyleve/Stuff/pull/554) | [ddb0a8546](https://github.com/kyleve/Stuff/commit/ddb0a85466d0ca8ee65e830a43f096e2fb72738e) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#553](https://github.com/kyleve/Stuff/pull/553) | [3d33d33f6](https://github.com/kyleve/Stuff/commit/3d33d33f68324d2fee02822084880b467e9ab3e1) | Selected | 1/0 | 506.7 | 1499.2 | 1274.1 | 1287.8 | 198.2 | 451.4 | Unit | Yes |
| [#552](https://github.com/kyleve/Stuff/pull/552) | [299b73b27](https://github.com/kyleve/Stuff/commit/299b73b27813224f2958dc52027370430463ea37) | Selected | 1/0 | 653.1 | 1499.2 | 1274.1 | 1287.8 | 242.2 | 451.4 | Unit | Yes |
| [#550](https://github.com/kyleve/Stuff/pull/550) | [36c2e6351](https://github.com/kyleve/Stuff/commit/36c2e6351382ac0ec7185cfb9304ad72fca2dd5c) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#548](https://github.com/kyleve/Stuff/pull/548) | [9dd17d9b5](https://github.com/kyleve/Stuff/commit/9dd17d9b5ccbd7c45892bf1a12d399471b038e53) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#549](https://github.com/kyleve/Stuff/pull/549) | [88e17d8fb](https://github.com/kyleve/Stuff/commit/88e17d8fb891e6a75d73f0abab61cdee7a8b1286) | Selected | 4/1 | 359.6 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#546](https://github.com/kyleve/Stuff/pull/546) | [798c61cc4](https://github.com/kyleve/Stuff/commit/798c61cc4cab5c64c68eebdbcbeba3a793cd87ac) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#544](https://github.com/kyleve/Stuff/pull/544) | [1b04fdd2c](https://github.com/kyleve/Stuff/commit/1b04fdd2ccf58e0c92d44ab978fafcf32f9c4c91) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#543](https://github.com/kyleve/Stuff/pull/543) | [b9757eccf](https://github.com/kyleve/Stuff/commit/b9757eccf9678e52ad9f19911e09d5d157cf8f1e) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#542](https://github.com/kyleve/Stuff/pull/542) | [e73c61387](https://github.com/kyleve/Stuff/commit/e73c613876ece722b11da6f87fcffde22f2f87c0) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#541](https://github.com/kyleve/Stuff/pull/541) | [dd612e9c4](https://github.com/kyleve/Stuff/commit/dd612e9c43958d45a641ff2a01b471b304561422) | Selected | 1/6 | 653.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#539](https://github.com/kyleve/Stuff/pull/539) | [e19c63f77](https://github.com/kyleve/Stuff/commit/e19c63f7709320bd5d2e677d56f1ab44496b216c) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#495](https://github.com/kyleve/Stuff/pull/495) | [1678df612](https://github.com/kyleve/Stuff/commit/1678df6123dc49946284ae1de99b8c2c74050a06) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#537](https://github.com/kyleve/Stuff/pull/537) | [f670aceea](https://github.com/kyleve/Stuff/commit/f670aceeaccbc21a2a2a382c833ff5e596a69f79) | Selected | 4/1 | 359.6 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#535](https://github.com/kyleve/Stuff/pull/535) | [bb454d094](https://github.com/kyleve/Stuff/commit/bb454d094bf1d48e1bffe85f1c2ea57ecd8a2f73) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#523](https://github.com/kyleve/Stuff/pull/523) | [cd293e851](https://github.com/kyleve/Stuff/commit/cd293e8517d921bf20071cbf35c0cdf6ac099d17) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#521](https://github.com/kyleve/Stuff/pull/521) | [a76094de5](https://github.com/kyleve/Stuff/commit/a76094de5285a019791e9fddaf814bcb60fec780) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#520](https://github.com/kyleve/Stuff/pull/520) | [e74357058](https://github.com/kyleve/Stuff/commit/e7435705800c0a4150121372a0398373f97279cc) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#518](https://github.com/kyleve/Stuff/pull/518) | [161650d49](https://github.com/kyleve/Stuff/commit/161650d49268eb72880ab5f9cebe4e63e4a0a202) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#517](https://github.com/kyleve/Stuff/pull/517) | [e92bcb39a](https://github.com/kyleve/Stuff/commit/e92bcb39a1595e33229e5b547f47fc2f39ea3abb) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#516](https://github.com/kyleve/Stuff/pull/516) | [e07e95cee](https://github.com/kyleve/Stuff/commit/e07e95ceeed560fb2de44361ec527ea2f7dfc34b) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#515](https://github.com/kyleve/Stuff/pull/515) | [ef24487d8](https://github.com/kyleve/Stuff/commit/ef24487d818fdae92102555f63cbb709e3fc9d3f) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#514](https://github.com/kyleve/Stuff/pull/514) | [7908ae719](https://github.com/kyleve/Stuff/commit/7908ae719494d0f29ff614c6b415284b34855724) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#512](https://github.com/kyleve/Stuff/pull/512) | [0312c6294](https://github.com/kyleve/Stuff/commit/0312c629439cc4e6f3cf8ab31bdf344078b63b7d) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#511](https://github.com/kyleve/Stuff/pull/511) | [7874e4292](https://github.com/kyleve/Stuff/commit/7874e429213b46b5b48e3e5f043b2c4e5a9141f8) | Selected | 7/6 | 178.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#509](https://github.com/kyleve/Stuff/pull/509) | [7f0efe1fd](https://github.com/kyleve/Stuff/commit/7f0efe1fd1c50419df2e3bd290b6018fe31886f0) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#510](https://github.com/kyleve/Stuff/pull/510) | [a7d41aa02](https://github.com/kyleve/Stuff/commit/a7d41aa02365dacf579cef4a928e02daccf54a1f) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#508](https://github.com/kyleve/Stuff/pull/508) | [e62d99793](https://github.com/kyleve/Stuff/commit/e62d997930347944874322ded4e62171c6880cb1) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#506](https://github.com/kyleve/Stuff/pull/506) | [7a253841d](https://github.com/kyleve/Stuff/commit/7a253841d6de9edcf5438ee7b2af07c80364e265) | Selected | 4/1 | 192.8 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#505](https://github.com/kyleve/Stuff/pull/505) | [6676b36bc](https://github.com/kyleve/Stuff/commit/6676b36bcd7a6dac1d0f7c72784b1d44b7c7f742) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#507](https://github.com/kyleve/Stuff/pull/507) | [15195ab9c](https://github.com/kyleve/Stuff/commit/15195ab9c8abfbf61f5619ecdd6e680887487211) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#504](https://github.com/kyleve/Stuff/pull/504) | [ff3f9ec8d](https://github.com/kyleve/Stuff/commit/ff3f9ec8df1d7901312624cba805be868f1f7345) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#503](https://github.com/kyleve/Stuff/pull/503) | [2193072f6](https://github.com/kyleve/Stuff/commit/2193072f6a1c988f797c77c14c3b6cf0923d8ca0) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#499](https://github.com/kyleve/Stuff/pull/499) | [c954dd31e](https://github.com/kyleve/Stuff/commit/c954dd31e00b85b7a473ec341d193e188106867e) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#502](https://github.com/kyleve/Stuff/pull/502) | [8d433cde9](https://github.com/kyleve/Stuff/commit/8d433cde9a80ff9bc683ee03bac1a16d708bf980) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#498](https://github.com/kyleve/Stuff/pull/498) | [96f5bf0f1](https://github.com/kyleve/Stuff/commit/96f5bf0f1685de259d7ff080842b8092f9a950d2) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#496](https://github.com/kyleve/Stuff/pull/496) | [2e27fc5ba](https://github.com/kyleve/Stuff/commit/2e27fc5ba8d6d9f37daf39f83848af34a8b3ef5a) | Selected | 7/6 | 178.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#372](https://github.com/kyleve/Stuff/pull/372) | [b629d56ac](https://github.com/kyleve/Stuff/commit/b629d56ac44a3f2a5ea59c3d6ae9cd5401f37674) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#483](https://github.com/kyleve/Stuff/pull/483) | [b5be3562e](https://github.com/kyleve/Stuff/commit/b5be3562eec7a90459272394411bf146f33d2325) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#378](https://github.com/kyleve/Stuff/pull/378) | [74cb4df8d](https://github.com/kyleve/Stuff/commit/74cb4df8da4dd6979607bfb8d8a409a4c2031c2d) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#494](https://github.com/kyleve/Stuff/pull/494) | [12de429a5](https://github.com/kyleve/Stuff/commit/12de429a5a9b0d933a38dc2e6fbda93b399fac04) | Selected | 4/2 | 493.6 | 372.4 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#377](https://github.com/kyleve/Stuff/pull/377) | [2aedf67c7](https://github.com/kyleve/Stuff/commit/2aedf67c709513d0428e280fede185413cd8f62e) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#376](https://github.com/kyleve/Stuff/pull/376) | [b3546eb59](https://github.com/kyleve/Stuff/commit/b3546eb59b8c9275e8fc4a4c4fda54a089ce2ea5) | Selected | 9/4 | 478.9 | 341.8 | 0.0 | 0.0 | 71.7 | 71.7 | Snapshot 1 | Yes |
| [#492](https://github.com/kyleve/Stuff/pull/492) | [ef90cacdd](https://github.com/kyleve/Stuff/commit/ef90cacdd91dee084c0d0c7639b3426b7d42a6bf) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#491](https://github.com/kyleve/Stuff/pull/491) | [0e95a9398](https://github.com/kyleve/Stuff/commit/0e95a9398c382ff6d28ef46c9474718023f14ccb) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#486](https://github.com/kyleve/Stuff/pull/486) | [c9a5cbda9](https://github.com/kyleve/Stuff/commit/c9a5cbda98c4b9f8f6aed0313d2ce2cf594cc79b) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#490](https://github.com/kyleve/Stuff/pull/490) | [91b3542e4](https://github.com/kyleve/Stuff/commit/91b3542e44b930c1abdc98e8514525fafa716a34) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#488](https://github.com/kyleve/Stuff/pull/488) | [655ad4e04](https://github.com/kyleve/Stuff/commit/655ad4e04b80e89946b276ceb8efe7818cb301d5) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#487](https://github.com/kyleve/Stuff/pull/487) | [c473b11a9](https://github.com/kyleve/Stuff/commit/c473b11a9226afa689eabd95511dde1cc46eeea4) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#489](https://github.com/kyleve/Stuff/pull/489) | [f61c80441](https://github.com/kyleve/Stuff/commit/f61c80441b47393244ceb7c780afef281bf5e6e2) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#485](https://github.com/kyleve/Stuff/pull/485) | [bbe90c4c5](https://github.com/kyleve/Stuff/commit/bbe90c4c58d9d458382335418a18a5dccb434e87) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#479](https://github.com/kyleve/Stuff/pull/479) | [ea950e0f8](https://github.com/kyleve/Stuff/commit/ea950e0f8272750e674929d7b01f83350cff4496) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#477](https://github.com/kyleve/Stuff/pull/477) | [944f17dc7](https://github.com/kyleve/Stuff/commit/944f17dc776fbab235627e9c88f5d57fd4761dfe) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#478](https://github.com/kyleve/Stuff/pull/478) | [9f9f83329](https://github.com/kyleve/Stuff/commit/9f9f83329415f839a473f41bd6dd7957ca252bf4) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#469](https://github.com/kyleve/Stuff/pull/469) | [264d27ece](https://github.com/kyleve/Stuff/commit/264d27ece6197357360d7b09f4eb6c0cb84183f2) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#474](https://github.com/kyleve/Stuff/pull/474) | [a22b60952](https://github.com/kyleve/Stuff/commit/a22b6095254d391cb70a2dbed61943647ecbdeab) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#471](https://github.com/kyleve/Stuff/pull/471) | [e3ccf86e2](https://github.com/kyleve/Stuff/commit/e3ccf86e285b3700237ab315352c4a11cdf8e7e3) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#470](https://github.com/kyleve/Stuff/pull/470) | [44760dc17](https://github.com/kyleve/Stuff/commit/44760dc17c00ae72f294d32eecc6f6935a0956a9) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#467](https://github.com/kyleve/Stuff/pull/467) | [93062f7c9](https://github.com/kyleve/Stuff/commit/93062f7c97b7a7163622d2a68c972514d00d1fad) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#465](https://github.com/kyleve/Stuff/pull/465) | [c95d81f7d](https://github.com/kyleve/Stuff/commit/c95d81f7d87c879ce9b3a534e680d4e67b231a75) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#453](https://github.com/kyleve/Stuff/pull/453) | [a9e5fae88](https://github.com/kyleve/Stuff/commit/a9e5fae88aa3e52ed22ca88a079ee48431b9beec) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#452](https://github.com/kyleve/Stuff/pull/452) | [3af5c30e4](https://github.com/kyleve/Stuff/commit/3af5c30e41ec3a8323e66be8e58b202f91b23b3c) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#451](https://github.com/kyleve/Stuff/pull/451) | [78a288828](https://github.com/kyleve/Stuff/commit/78a2888281f9ef8debc77b29e2440c609e0edf6d) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#441](https://github.com/kyleve/Stuff/pull/441) | [a82a7a451](https://github.com/kyleve/Stuff/commit/a82a7a4511f3f0477c9825bbaeae2a882b2fecd4) | Docs skip | 0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — |
| [#449](https://github.com/kyleve/Stuff/pull/449) | [123272e3f](https://github.com/kyleve/Stuff/commit/123272e3f2361a9fa2d23879d654eede6d90b072) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#450](https://github.com/kyleve/Stuff/pull/450) | [033c61e12](https://github.com/kyleve/Stuff/commit/033c61e1248d77fd07d7d440ae66a05c32e631a1) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#446](https://github.com/kyleve/Stuff/pull/446) | [63733b2cd](https://github.com/kyleve/Stuff/commit/63733b2cd5bea853c9a776a3e27164a86e9311e3) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#444](https://github.com/kyleve/Stuff/pull/444) | [e1377fb74](https://github.com/kyleve/Stuff/commit/e1377fb74cf741208a9118e9940bfd1c2d53d58c) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#443](https://github.com/kyleve/Stuff/pull/443) | [e873e1b2d](https://github.com/kyleve/Stuff/commit/e873e1b2dac9f383b625e292e1df097bec63680e) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#440](https://github.com/kyleve/Stuff/pull/440) | [66baf2a06](https://github.com/kyleve/Stuff/commit/66baf2a063828f1b06725b2110655bac42d09557) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#420](https://github.com/kyleve/Stuff/pull/420) | [850614889](https://github.com/kyleve/Stuff/commit/8506148893432a608b31f6e0651d06f4f674cbb5) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#419](https://github.com/kyleve/Stuff/pull/419) | [c3acfd09d](https://github.com/kyleve/Stuff/commit/c3acfd09d96a0d04e61e576c364537c6885ccd60) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#417](https://github.com/kyleve/Stuff/pull/417) | [a9bce0736](https://github.com/kyleve/Stuff/commit/a9bce073673c07a2c073c0122cef5246402049fe) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#415](https://github.com/kyleve/Stuff/pull/415) | [2b50b0191](https://github.com/kyleve/Stuff/commit/2b50b01914ed835e1eb39cb5512957196055a902) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#442](https://github.com/kyleve/Stuff/pull/442) | [beb62208e](https://github.com/kyleve/Stuff/commit/beb62208e49848e373ec72f94deee3412dd6421a) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#270](https://github.com/kyleve/Stuff/pull/270) | [209b1b3e2](https://github.com/kyleve/Stuff/commit/209b1b3e29adf7263700565bf4d299f2aeff9cd7) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#439](https://github.com/kyleve/Stuff/pull/439) | [1832d5336](https://github.com/kyleve/Stuff/commit/1832d5336589a0d28998001e7e37f3ac3f0f2231) | Selected | 7/6 | 178.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#438](https://github.com/kyleve/Stuff/pull/438) | [615df06e1](https://github.com/kyleve/Stuff/commit/615df06e18241d5d01a0faf44219d8696af38897) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#436](https://github.com/kyleve/Stuff/pull/436) | [820030f68](https://github.com/kyleve/Stuff/commit/820030f6847db856a40393aa2e40814b1bef60de) | Selected | 3/2 | 503.3 | 86.9 | 27.8 | 83.2 | 26.1 | 26.1 | Snapshot 0 | No |
| [#362](https://github.com/kyleve/Stuff/pull/362) | [ef859d728](https://github.com/kyleve/Stuff/commit/ef859d728e4319d4158bb14526e74122d4243cc0) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#435](https://github.com/kyleve/Stuff/pull/435) | [b41fa9fd2](https://github.com/kyleve/Stuff/commit/b41fa9fd2b548499430b290417ad2c080092786c) | Selected | 7/6 | 178.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#400](https://github.com/kyleve/Stuff/pull/400) | [529efba7a](https://github.com/kyleve/Stuff/commit/529efba7ab91852810e668ba36200f79eac3e27b) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#434](https://github.com/kyleve/Stuff/pull/434) | [b06b6270d](https://github.com/kyleve/Stuff/commit/b06b6270d0f178147be13ba39a1656e61c659474) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#422](https://github.com/kyleve/Stuff/pull/422) | [2dae40af2](https://github.com/kyleve/Stuff/commit/2dae40af2d768f151666df626906c0051805c638) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#433](https://github.com/kyleve/Stuff/pull/433) | [2bf2ac2f5](https://github.com/kyleve/Stuff/commit/2bf2ac2f5d181d54f8367b0773fa063d7cd06eb3) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#432](https://github.com/kyleve/Stuff/pull/432) | [58b526b7a](https://github.com/kyleve/Stuff/commit/58b526b7aa639b6ff8ef9b66465247f29eaa5e39) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#431](https://github.com/kyleve/Stuff/pull/431) | [806c4fc62](https://github.com/kyleve/Stuff/commit/806c4fc62da428da2d9804177decc733b01f35ff) | Selected | 0/1 | 1517.3 | 761.3 | 1274.1 | 1287.8 | 228.4 | 228.4 | Snapshot 0 | Yes |
| [#430](https://github.com/kyleve/Stuff/pull/430) | [3914e2250](https://github.com/kyleve/Stuff/commit/3914e22501f66e08a4fa3d6fe416859faf624b3e) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#428](https://github.com/kyleve/Stuff/pull/428) | [65b3b141e](https://github.com/kyleve/Stuff/commit/65b3b141e38f654cc672d93eef1022faf0de22e0) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#429](https://github.com/kyleve/Stuff/pull/429) | [f7ce0b964](https://github.com/kyleve/Stuff/commit/f7ce0b96413efbc6b608f03ed081a49f02fae293) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#427](https://github.com/kyleve/Stuff/pull/427) | [d8c338c78](https://github.com/kyleve/Stuff/commit/d8c338c7861444d0286375e2f4bbb860e2271b0f) | Selected | 6/2 | 354.0 | 398.3 | 0.0 | 0.0 | 71.7 | 71.7 | Snapshot 1 | Yes |
| [#426](https://github.com/kyleve/Stuff/pull/426) | [bef30c92a](https://github.com/kyleve/Stuff/commit/bef30c92a002e9db4ef1ec13eb82099354844a50) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |
| [#421](https://github.com/kyleve/Stuff/pull/421) | [e80780d5b](https://github.com/kyleve/Stuff/commit/e80780d5ba27bd135fba349eaaf136d5daf08d83) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#416](https://github.com/kyleve/Stuff/pull/416) | [5d4655799](https://github.com/kyleve/Stuff/commit/5d46557995d5d9a471ba9337922dc597b966ccf0) | Selected | 3/1 | 503.3 | 419.1 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#423](https://github.com/kyleve/Stuff/pull/423) | [536f52f53](https://github.com/kyleve/Stuff/commit/536f52f53a0251a6dc516cc56c6337a320f8a6f6) | Selected | 1/6 | 653.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#361](https://github.com/kyleve/Stuff/pull/361) | [ebb314a35](https://github.com/kyleve/Stuff/commit/ebb314a35339e0e0b580bb98fa9b64238df7f695) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#359](https://github.com/kyleve/Stuff/pull/359) | [f9efcb490](https://github.com/kyleve/Stuff/commit/f9efcb490ae1dc347086128d7eae23f6727b908a) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | Yes |
| [#358](https://github.com/kyleve/Stuff/pull/358) | [a778596b8](https://github.com/kyleve/Stuff/commit/a778596b8ef0243527e258f52c153a2c22f430c1) | Selected | 4/2 | 493.6 | 372.4 | 27.8 | 83.2 | 80.0 | 80.0 | Snapshot 1 | Yes |
| [#414](https://github.com/kyleve/Stuff/pull/414) | [3f1c811f6](https://github.com/kyleve/Stuff/commit/3f1c811f6735898782514ab9d81e7f3ff947b7a5) | Full fallback | 22/6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | Snapshot 0 | No |

## Selected bundles

These 12 distinct selections account for all 29 narrowed validations. PRs within a row produce the same worker estimate at a given calibration.

| PRs | Selected logical bundles |
| --- | --- |
| 553 | `WhereUITests` |
| 552 | `SnapshotKitTestingTests` |
| 548, 521, 520, 518, 516, 515, 514, 512, 504, 438, 421, 416 | `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 549, 537 | `WhereCoreTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 541, 423 | `FlyoverSnapshotTests`, `InspectorSnapshotTests`, `InstallerKitUISnapshotTests`, `PeriscopeToolsSnapshotTests`, `SnapshotKitTestingTests`, `ToolsSnapshotTests`, `WhereUISnapshotTests` |
| 511, 496, 439, 435 | `FlyoverSnapshotTests`, `FlyoverTests`, `InspectorSnapshotTests`, `InstallerKitUISnapshotTests`, `InstallerKitUITests`, `PeriscopeToolsSnapshotTests`, `SnapshotKitTestingTests`, `SnapshotKitTests`, `ToolsSnapshotTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 506 | `SnapshotKitTestingTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 494, 358 | `FlyoverSnapshotTests`, `FlyoverTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 376 | `BroadwayCatalogTests`, `BroadwayCoreTests`, `BroadwayUITests`, `FlyoverSnapshotTests`, `FlyoverTests`, `InstallerKitUISnapshotTests`, `InstallerKitUITests`, `PeriscopeToolsSnapshotTests`, `PeriscopeToolsTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 436 | `ToolsSnapshotTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |
| 431 | `ToolsSnapshotTests` |
| 427 | `InstallerKitTests`, `InstallerKitUISnapshotTests`, `InstallerKitUITests`, `WhereCoreTests`, `WhereIntentsTests`, `WhereTests`, `WhereUISnapshotTests`, `WhereUITests` |

## Fixture cache inputs used for the comparison

A paid diff invalidates the hypothetical fixture entry if it changes either side of a registered `site.icon` or `site.darkIcon` path from `.github/installer-apps.json`. It also invalidates the entry if it touches either directory tree or any of the following files.

| Kind | Paths |
| --- | --- |
| Complete directory trees | `Tools/InstallerKit/`, `Tools/Tests/Fixtures/` |
| Registry, renderer and helpers | `.github/installer-apps.json`, `Tools/astro_site.py`, `Tools/repository.py`, `Tools/circleci_pipeline.py` |
| Configuration and versions | `.mise.toml`, `.npmrc`, `.python-version`, `.xcode-version`, `.xcode-build-version`, `package.json`, `package-lock.json`, `Project.swift`, `.circleci/continue.yml` |

The screen uses both sides of the changed-file list and artwork registry. For the earlier-head supplement, the left side is the merge base. A missing registry is a miss. The oldest paid landed diff changes a keyed input. The calculation assumes later unchanged keys can be restored from a compatible previously built base. These broad paths support an opportunity estimate. An implementation would need to verify every generator dependency and measure real hit, miss and restore behavior.
