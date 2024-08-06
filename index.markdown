---
# Feel free to add content and custom Front Matter to this file.
# To modify the layout, see https://jekyllrb.com/docs/themes/#overriding-theme-defaults

layout: post
title: Optimizing Tail Latency in a Heterogeneous Environment with Istio, Envoy, and a Custom Kubernetes Operator
---

## Abstract

This article details our approach to optimizing tail latency in a heterogeneous Kubernetes environment using Istio, Envoy, and a custom Kubernetes operator. We identified performance disparities caused by hardware variations, developed a solution that dynamically adjusts load balancing weights based on real-time CPU metrics, and achieved significant reductions in tail latency. Our findings demonstrate the effectiveness of adaptive load balancing strategies in improving microservices performance and reliability.

## Introduction

Running microservices in a Kubernetes environment often involves dealing with various hardware generations and CPU architectures. In our infrastructure, we observed high tail latency in some of our services despite using Istio and Envoy as our service mesh. This article details our journey in identifying the root cause of this issue and implementing a custom solution using a Kubernetes operator to optimize tail latency. Tail latency optimization is crucial in microservices architectures as it directly impacts user experience and system reliability.

## Identifying the Challenge

We run multiple hardware generations and different CPU architectures within our Kubernetes clusters. Our service mesh, composed of Istio for control and Envoy for the data plane, uses the `LEAST_REQUEST` load-balancing algorithm to distribute traffic between services. However, we noticed that certain services experienced significantly high tail latency. Upon investigation, we discovered that the disparities in hardware capabilities were the main cause of this issue.

## Understanding the Problem

Tail latency refers to the latency experienced by the slowest requests, typically measured at the 95th, 99th, or 99.9th percentile. High tail latency can negatively impact user experience and indicate underlying performance bottlenecks. In our case, tail latency matters because it represents the worst-case scenario for our service response times.

The default load balancing strategy in Envoy works well in homogeneous environments but struggles when hardware performance is uneven, leading to inefficient request distribution and high tail latency.

## Developing the Solution

To address this problem, we developed a custom Kubernetes operator. This operator dynamically adjusts the load balancing weights of Envoy proxies using Istio's CRD called ServiceEntry. Here's how we implemented our solution:

### Step 1: Measuring CPU Utilization of Pods

We deployed a dedicated VictoriaMetrics cluster to collect real-time CPU usage statistics for each pod. Our operator interfaces with the VictoriaMetrics API to gather this data, calculating the average CPU usage for each service by aggregating individual pod metrics.

### Step 2: Calculating Weight Adjustments

Based on the average CPU usage, the operator determines the "distance" of each pod's CPU usage from the average. Pods with CPU usage below the average are assigned higher weights, indicating they can handle more requests. Conversely, pods with higher-than-average CPU usage receive lower weights to prevent them from becoming bottlenecks.

### Step 3: Applying the Weights

The calculated weights are applied to the Envoy proxies via Istio's ServiceEntry resources. This dynamic adjustment ensures that request distribution considers each pod's real-time performance, optimizing load balancing to reduce tail latency.

![alt text](images/high-level-design.png)
<figcaption><i>Fig 1: High Level Design:</i></figcaption>
# Results and Impact

To evaluate the impact of our optimization strategy, we conducted extensive testing using a set of 15 Nginx pods, each executing a Lua script to calculate different Fibonacci numbers. This setup introduced variability in compute load, reflecting our heterogeneous environment.

### Testing Methodology

We used Fortio to generate load at a rate of 1,500 requests per second (rps). The Nginx pods were configured to calculate Fibonacci numbers ranging from 25 to 29, creating varying levels of CPU usage. Here's the breakdown of our pod setup:

- Pods calculating Fibonacci number for 25:
  - sleep-lior-2-6794d4cfdc-2gs9b
  - sleep-lior-2-6794d4cfdc-6r6lg
  - sleep-lior-2-6794d4cfdc-rvmd2

- Pods calculating Fibonacci number for 26:
  - sleep-lior-2-6794d4cfdc-jgxqg
  - sleep-lior-2-6794d4cfdc-stjzd

- Pods calculating Fibonacci number for 27:
  - sleep-lior-2-6794d4cfdc-7rrwr
  - sleep-lior-2-6794d4cfdc-gv856
  - sleep-lior-2-6794d4cfdc-jz462
  - sleep-lior-2-6794d4cfdc-kr64w
  - sleep-lior-2-6794d4cfdc-kxhwx
  - sleep-lior-2-6794d4cfdc-m2xcx
  - sleep-lior-2-6794d4cfdc-p594m
  - sleep-lior-2-6794d4cfdc-qnlnl
  - sleep-lior-2-6794d4cfdc-tffd9

- Pod calculating Fibonacci number for 29:
  - sleep-lior-2-6794d4cfdc-mp8sn

This distribution of Fibonacci calculations across pods simulates a heterogeneous environment where different nodes have varying computational capabilities. The pods calculating lower Fibonacci numbers (25 and 26) represent faster or less loaded nodes, while those calculating higher numbers (27 and especially 29) represent slower or more heavily loaded nodes.

### Before Optimization

- Total CPU Usage: ~10 CPUs for all pods
![Total CPU usage before optimization](images/total-cpu-usage-before.png)
    <figcaption><i>Fig 2: Total CPU usage before optimization:
    sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate{container!="POD", container=~"sleep-lior-2"})
    </i></figcaption>
- CPU Usage Range: 2.2 (highest pod) to 0.2 (lowest pod)
![alt text](images/per-pod-cpu-before.png)
    <figcaption><i>Fig 3: Per-pod CPU usage before optimization:
    sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate{container!="POD", container="sleep-lior-2"}) by (pod)</i></figcaption> 
- Service Response Time:
![alt text](images/latencies-before.png)
    <figcaption><i>Fig 4: Service latencies before optimization:
    histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    histogram_quantile(0.90, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    </i></figcaption>
  - p50 Latency: 14ms (ranging from 50ms to 6ms)
  ![alt text](images/per-pod-p50-before.png)
    <figcaption><i>Fig 5: Per-pod p50 latency before optimization:
    histogram_quantile(0.5, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>
  - p90 Latency: 38ms (ranging from 100ms to 10ms)
  ![alt text](images/per-pod-p90-before.png)
    <figcaption><i>Fig 6: Per-pod p90 latency before optimization:
    histogram_quantile(0.9, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>  
  - p95 Latency: 47ms (ranging from 170ms to 17ms)
  ![alt text](images/per-pod-p95-before.png)
    <figcaption><i>Fig 7: Per-pod p95 latency before optimization:
    histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>    
  - p99 Latency: 93ms (ranging from 234ms to 23ms) 
  ![alt text](images/per-pod-p99-before.png)
    <figcaption><i>Fig 8: Per-pod p99 latency before optimization:
    histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>
- Request Rate per Pod: 100 requests per second (uniform)
![alt text](images/per-pod-rps-before.png)
    <figcaption><i>Fig 9: Per-pod request rate before optimization:
    sum(rate(istio_requests_total{container!="POD",destination_canonical_service=~"sleep-lior-2",pod=~"sleep-lior-2.*"})) by (pod)</i></figcaption>
### After Optimization

- Total CPU Usage: Decreased to 8 CPUs
![alt text](images/total-cpu-usage.png)
    <figcaption><i>Fig 10: Total CPU usage after optimization:
    sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate{container!="POD", container=~"sleep-lior-2"})
    </i></figcaption>
- CPU Usage Range: 0.6 (highest pod) to 0.45 (lowest pod)
![alt text](images/per-pod-cpu.png)
    <figcaption><i>Fig 11: Per-pod CPU usage after optimization:
    sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate{container!="POD", container="sleep-lior-2"}) by (pod)</i></figcaption> 
- Service Response Time:
![alt text](images/Latency-Reductions.png)
    <figcaption><i>Fig 12: Service latencies after optimization:
    histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    histogram_quantile(0.90, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2"}[2m])) by (le,destination_canonical_service))
    </i></figcaption>
  - p50 Latency: 13.2ms (ranging from 23ms to 9ms)
  ![alt text](images/per-pod-p50.png)
    <figcaption><i>Fig 13: Per-pod p50 latency after optimization:
    histogram_quantile(0.5, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>  
  - p90 Latency: 24ms (ranging from 46ms to 21ms)
  ![alt text](images/per-pod-p90.png)
    <figcaption><i>Fig 14: Per-pod p90 latency after optimization:
    histogram_quantile(0.9, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>    
  - p95 Latency: 33ms (ranging from 50ms to 23ms)
  ![alt text](images/per-pod-p95.png)
    <figcaption><i>Fig 15: Per-pod p95 latency after optimization:
    histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>     
  - p99 Latency: 47ms (ranging from 92ms to 24ms)
  ![alt text](images/per-pod-p99.png)
    <figcaption><i>Fig 16: Per-pod p99 latency after optimization:
    histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_canonical_service="sleep-lior-2",request_protocol="http",response_code=~"2.*",pod=~"sleep-lior-2.*"}[2m])) by (le,pod))</i></figcaption>    
- Request Rate per Pod: Adjusted, ranging from 25 rp/s to 224 rp/s
![alt text](images/per-pod-rps.png)
    <figcaption><i>Fig 17: Per-pod request rate after optimization:
    sum(rate(istio_requests_total{container!="POD",destination_canonical_service=~"sleep-lior-2",pod=~"sleep-lior-2.*"})) by (pod)</i></figcaption>

### Interpretation of Results

The optimization demonstrated significant performance improvements:

- **CPU Usage Reduction:** Total usage decreased from 10 CPUs to 8 CPUs, indicating more efficient resource utilization.
- **Latency Reductions:** Significant improvements across all percentiles, with p99 latency nearly halved.
- **Balanced Load Distribution:** Request rates adjusted dynamically, ensuring faster pods handle more requests and slower pods handle fewer, contributing to lower latencies and balanced resource usage.

## Conclusion

By focusing on CPU metrics and dynamically adjusting load balancing weights, we optimized the performance of our microservices running in a heterogeneous hardware environment. This approach, facilitated by a custom Kubernetes operator and leveraging Istio and Envoy, enabled us to reduce tail latency and improve overall system reliability significantly.

Our experience demonstrates that adapting load-balancing strategies to account for hardware variability can overcome performance disparities and create a more responsive and robust microservices architecture. This approach has broader implications for the industry, particularly for organizations managing diverse infrastructure or transitioning between hardware generations.

## Research and Community Engagement

Our journey began with extensive research, including Google searches that led us to an article detailing Google's innovative methods for similar issues. This discovery was transformative, affirming that load balancing of least connections is a common challenge. Google developed an internal mechanism called Prequal, which optimizes load balancing by minimizing real-time latency and requests-in-flight (RIF), a concept not found in Envoy's load balancing.

Before developing our Kubernetes operator, we engaged with the community to explore existing solutions. This approach provided valuable insights and saved time. For example, during our tests, we encountered a bug that the community resolved in less than 24 hours, demonstrating the power of collaborative problem-solving.

We raised an issue on Istio's GitHub repository (https://github.com/istio/istio/issues/50968) and witnessed a swift response from the community, highlighting the importance of collaboration in open-source projects.

## Future Work

Our Kubernetes operator is running in production and performing well. We've successfully implemented the first step of balancing CPU resources, and it's effective so far. Moving forward, our plans include:

1. Monitoring and Iteration: Continuously monitoring the performance and making necessary adjustments.
2. Exploring Additional Metrics: Considering other metrics such as memory usage or network latency for finer load balancing.
3. Community Collaboration: Working with the Istio and Envoy communities to contribute our findings and improvements back to the open-source projects.

We believe our approach can serve as a blueprint for others facing similar challenges in heterogeneous Kubernetes environments, and we look forward to further optimizations and community contributions.

## Appendix: Implementation Details

For the detailed implementation of our Fibonacci calculator used in the Nginx pods, please refer to our [Lua script](./fibonacci_calculator.lua).

For the complete codebase and additional implementation details, please visit our GitHub repository:
[Istio-adaptive-least-request](https://github.com/liorfranko/Istio-adaptive-least-request)
