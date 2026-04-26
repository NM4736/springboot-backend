# Observability Stack Overview: Prometheus, Grafana, Loki & Alertmanager

This document provides a summary of the modern observability stack, how the components work together, and answers to specific questions discussed.

## 1. High-Level Architecture for Revision

Here is a simple text-based diagram showing how the tools connect to your application.

```
┌───────────────────────────┐      ┌───────────────────────────┐
│      YOUR APPLICATION     │      │                           │
│ (e.g., Spring Boot App)   │      │         GRAFANA           │
│                           │      │   (The Unified Dashboard)   │
├───────────────────────────┤      │                           │
│                           │      └─────┬─────────────────┬───┘
│  - Writes Logs to File    │            │                 │
│  - Exposes /metrics       │            │ Queries         │ Queries
└───────────┬───────────┬───┘            │ Metrics         │ Logs
            │           │                ▼                 ▼
┌───────────▼─────────┐ │      ┌──────────────────┐   ┌──────────────────┐
│    PROMPTAIL AGENT  │ │      │    PROMETHEUS    │   │       LOKI       │
│ (Reads log files)   │ │      │ (Metrics DB)     │   │ (Log Aggregator) │
└───────────┬─────────┘ │      └─────────┬────────┘   └──────────────────┘
            │           │                │
            │ Forwards  │ Scrapes        │ Fires Alerts
            │ Logs      │ Metrics        │
            ▼           ▼                ▼
┌───────────┴───────────┴──────┐   ┌──────────────────┐
│      ALERTMANAGER            │◄──┤ (Alerting Rules) │
│ (Handles & Routes Alerts)    │   └──────────────────┘
└──────────────────────────────┘
```

**The Flow:**
1.  Your **Application** runs, producing logs and exposing metrics.
2.  **Prometheus** periodically "scrapes" the metrics endpoint.
3.  **Promtail** (Loki's agent) reads the log files and sends them to **Loki**.
4.  **Grafana** queries both Prometheus and Loki to build dashboards that give you a complete picture.
5.  **Prometheus** uses "alerting rules" to identify problems. If a rule is met, it fires an alert to **Alertmanager**.
6.  **Alertmanager** intelligently groups, silences, and routes the alert to the correct team (e.g., via Slack or PagerDuty).

---

## 2. The Tools Explained

### Prometheus: The Timekeeper and Health Checker
*   **What It Is:** A database specifically for collecting and storing **metrics** (numerical measurements over time, like CPU usage or request counts).
*   **How It Works:** It uses a **pull model**, "scraping" an HTTP endpoint (usually `/metrics`) on your application at regular intervals. Your application needs an **exporter** library to generate these metrics in the correct format.
*   **Its Job:** To tell you **WHAT** is happening in your system in an aggregated, numerical way.

### Grafana: The Artist and Storyteller
*   **What It Is:** A visualization platform for creating dashboards from various data sources.
*   **How It Works:** You connect Grafana to "Data Sources" like Prometheus and Loki. Then, you build "Dashboards" containing "Panels," where each panel runs a query (e.g., a PromQL query for Prometheus) to fetch and display data as a graph, gauge, or table.
*   **Its Job:** To visualize data from all your systems in one place, making it easy to spot trends and correlate events.

### Loki: The Super-Fast Log Librarian
*   **What It Is:** A log aggregation system designed to be cost-effective and fast.
*   **How It Works:** It collects logs from all your services into a central, searchable place. Its key innovation is that it **only indexes a small set of labels** for each log stream (e.g., `app="api"`, `cluster="us-east-1"`). This makes finding the right logs incredibly fast without the high cost of full-text indexing.
*   **Its Job:** To allow you to dig into the details and discover **WHY** something is happening by exploring the specific, contextual event data in your logs.

### Alertmanager: The Intelligent Alarm System
*   **What It Is:** A tool for handling alerts fired by a client (usually Prometheus). It manages deduplication, grouping, silencing, and routing of those alerts.
*   **How It Works:** Prometheus defines an "alerting rule" (e.g., `cpu > 90%`). When this rule is met, Prometheus sends an alert to Alertmanager. Alertmanager then applies its own logic to decide where to send the notification (Slack, PagerDuty, email, etc.).
*   **Its Job:** To prevent alert fatigue and ensure the right people are notified about the right problems at the right time.

---

## 3. Your Questions Answered (Q&A)

### Q: Who provides the exporter in my application? Is it the Actuator dependency? If yes, what is the exporter name?

**A:** You are correct! The **Spring Boot Actuator** is the foundation, but it works with another library to provide the specific exporter.

*   **The Exporter Dependency:** The dependency you need is **`micrometer-registry-prometheus`**.
*   **How It Works:**
    1.  **Spring Boot Actuator (`spring-boot-starter-actuator`):** Provides the core monitoring infrastructure and endpoints like `/actuator/`.
    2.  **Micrometer (`micrometer-core`):** A metrics facade included with Actuator. Your application reports all its metrics to Micrometer.
    3.  **Prometheus Registry (`micrometer-registry-prometheus`):** This is the actual exporter. It's a Micrometer plugin that formats the collected metrics into the text-based format Prometheus requires.

When these are combined, Actuator exposes the `/actuator/prometheus` endpoint, which Prometheus can then scrape.

### Q: If logs are collected by Prometheus, why is Loki needed? Or does Prometheus only collect metrics?

**A:** This is a crucial distinction. **Prometheus *only* collects metrics.** It cannot and does not collect logs. This is a deliberate design choice for efficiency and purpose.

*   **Metrics (Prometheus):** Are for aggregated, numerical data (the "what"). They are lightweight, structured, and cheap to store. You use them to understand the overall health and performance of your system.
    *   *Analogy:* A traffic counter on a highway reporting `cars_per_minute`.

*   **Logs (Loki):** Are for detailed, event-specific text data (the "why"). They are unstructured, rich in context, and more expensive to store and search. You use them to debug specific problems.
    *   *Analogy:* A helicopter reporter describing a specific car crash on that highway.

You need both tools to have a complete observability picture. You use Prometheus to get an alert that something is wrong (e.g., "API error rate is high"), and then you use Loki to find the specific error messages in the logs that explain why it's happening.
