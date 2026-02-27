#!/bin/bash
# ============================================================
# ЗАДАНИЕ 7: Мониторинг (Prometheus + Grafana + node_exporter)
# Использование: ./07_monitoring.sh [hq-srv|br-srv]
# ============================================================

ROLE="${1:-hq-srv}"

case "$ROLE" in

# =============================================
# HQ-SRV — основной сервер мониторинга
# =============================================
hq-srv)
    echo "=== ЗАДАНИЕ 7: Мониторинг (HQ-SRV) ==="

    echo "[1/3] Настройка prometheus.yml..."
    cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.bak 2>/dev/null || true

    cat > /etc/prometheus/prometheus.yml << 'PROMCONF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    scrape_timeout: 5s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['hq-srv:9100', 'br-srv:9100']
PROMCONF

    echo "[OK] prometheus.yml настроен"

    echo "[2/3] Запуск сервисов..."
    systemctl enable --now grafana-server
    systemctl enable --now prometheus
    systemctl enable --now prometheus-node_exporter

    systemctl restart grafana-server
    systemctl restart prometheus
    systemctl restart prometheus-node_exporter

    echo "[OK] Все сервисы мониторинга запущены"

    echo "[3/3] Статус сервисов..."
    for svc in grafana-server prometheus prometheus-node_exporter; do
        STATUS=$(systemctl is-active $svc)
        echo "  $svc: $STATUS"
    done

    echo ""
    echo "=== ИНСТРУКЦИЯ (в браузере на Клиенте) ==="
    echo "1. Откройте: http://hq-srv:3000"
    echo "2. Логин: admin / admin  ->  Новый пароль: P@ssw0rd"
    echo "3. Профиль (правый верхний) > Preferences > Language > Русский"
    echo ""
    echo "4. Иконка Grafana > Connections > Data Sources"
    echo "   > Add > Prometheus"
    echo "   > URL: http://localhost:9090"
    echo "   > Save & Test"
    echo ""
    echo "5. Иконка Grafana > Dashboards > Import"
    echo "   > ID: 11074 > Load"
    echo "   > DS_VICTORIAMETRICS -> выбрать 'prometheus'"
    echo "   > Import"
    echo ""
    echo "6. Открыть дашборд > ... > Edit"
    echo "   > Title: 'Информация по серверам' > Save"
    ;;

# =============================================
# BR-SRV — только node_exporter
# =============================================
br-srv)
    echo "=== ЗАДАНИЕ 7: node_exporter (BR-SRV) ==="
    systemctl enable --now prometheus-node_exporter
    systemctl restart prometheus-node_exporter
    STATUS=$(systemctl is-active prometheus-node_exporter)
    echo "[OK] prometheus-node_exporter: $STATUS"
    echo ""
    echo "Метрики доступны: http://$(hostname -I | awk '{print $1}'):9100/metrics"
    ;;

*)
    echo "Использование: $0 [hq-srv|br-srv]"
    exit 1
    ;;
esac
