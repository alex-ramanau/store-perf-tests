import random
from itertools import chain
import os

import six
from ulid import ULID
from flask import request, Response
from locust import (
    stats as locust_stats,
    runners as locust_runners,
    HttpUser,
    #FastHttpUser as HttpUser,
    task,
    events,
    between
)
from prometheus_client import Metric, REGISTRY, exposition
import psutil

MIN_USER_ID = 1
MAX_USER_ID = 10**6


class LocustCollector(object):
    registry = REGISTRY

    def __init__(self, environment, runner):
        self.environment = environment
        self.runner = runner
        #self.process = psutil.Process()

    def collect(self):
        # get some system metrics about locust process (for self-monitoring)
        #metric = Metric('locust_cpu_usage_percent', 'Locust CPU usage percent', 'gauge')
        #metric.add_sample('locust_cpu_usage_percent', value=self.process.cpu_percent(), labels={})
        #yield metric
        # collect metrics only when locust runner is spawning or running.
        runner = self.runner

        if runner and runner.state in (locust_runners.STATE_SPAWNING, locust_runners.STATE_RUNNING):
            stats = []
            for s in chain(locust_stats.sort_stats(runner.stats.entries), [runner.stats.total]):
                stats.append({
                    "method": s.method,
                    "name": s.name,
                    "num_requests": s.num_requests,
                    "num_failures": s.num_failures,
                    "avg_response_time": s.avg_response_time,
                    "min_response_time": s.min_response_time or 0,
                    "max_response_time": s.max_response_time,
                    "current_rps": s.current_rps,
                    "median_response_time": s.median_response_time,
                    "ninety_nineth_response_time": s.get_response_time_percentile(0.99),
                    # only total stats can use current_response_time, so sad.
                    #"current_response_time_percentile_95": s.get_current_response_time_percentile(0.95),
                    "avg_content_length": s.avg_content_length,
                    "current_fail_per_sec": s.current_fail_per_sec
                })

            # perhaps StatsError.parse_error in e.to_dict only works in python slave, take notices!
            errors = [e.to_dict() for e in six.itervalues(runner.stats.errors)]

            metric = Metric('locust_user_count', 'Swarmed users', 'gauge')
            metric.add_sample('locust_user_count', value=runner.user_count, labels={})
            yield metric
            
            metric = Metric('locust_errors', 'Locust requests errors', 'gauge')
            for err in errors:
                metric.add_sample('locust_errors', value=err['occurrences'],
                                  labels={'path': err['name'], 'method': err['method'],
                                          'error': err['error']})
            yield metric

            is_distributed = isinstance(runner, locust_runners.MasterRunner)
            if is_distributed:
                metric = Metric('locust_slave_count', 'Locust number of slaves', 'gauge')
                metric.add_sample('locust_slave_count', value=len(runner.clients.values()), labels={})
                yield metric

            metric = Metric('locust_fail_ratio', 'Locust failure ratio', 'gauge')
            metric.add_sample('locust_fail_ratio', value=runner.stats.total.fail_ratio, labels={})
            yield metric

            metric = Metric('locust_state', 'State of the locust swarm', 'gauge')
            metric.add_sample('locust_state', value=1, labels={'state': runner.state})
            yield metric

            metric = Metric('locust_cpu_usage', 'Locust CPU usage', 'gauge')
            metric.add_sample('locust_cpu_usage', value=runner.current_cpu_usage, labels={})
            yield metric

            metric = Metric('locust_cpu_warning_emitted', 'Locust CPU warning state', 'gauge')
            metric.add_sample('locust_cpu_warning_emitted', value=runner.cpu_warning_emitted, labels={})
            yield metric

            stats_metrics = ['avg_content_length', 'avg_response_time', 'current_rps', 'current_fail_per_sec',
                             'max_response_time', 'ninety_nineth_response_time', 'median_response_time', 'min_response_time',
                             'num_failures', 'num_requests']

            for mtr in stats_metrics:
                mtype = 'gauge'
                if mtr in ['num_requests', 'num_failures']:
                    mtype = 'counter'
                metric = Metric('locust_stats_' + mtr, 'Locust stats ' + mtr, mtype)
                for stat in stats:
                    # Aggregated stat's method label is None, so name it as Aggregated
                    # locust has changed name Total to Aggregated since 0.12.1
                    if 'Aggregated' != stat['name']:
                        metric.add_sample('locust_stats_' + mtr, value=stat[mtr],
                                          labels={'path': stat['name'], 'method': stat['method']})
                    else:
                        metric.add_sample('locust_stats_' + mtr, value=stat[mtr],
                                          labels={'path': stat['name'], 'method': 'Aggregated'})
                yield metric


@events.init.add_listener
def locust_init(environment, runner, **kwargs):
    print("locust init event received")
    if environment.web_ui and runner:
        @environment.web_ui.app.route("/metrics")
        def prometheus_exporter():
            registry = REGISTRY
            encoder, content_type = exposition.choose_encoder(request.headers.get('Accept'))
            if 'name[]' in request.args:
                registry = REGISTRY.restricted_registry(request.args.get('name[]'))
            body = encoder(registry)
            return Response(body, content_type=content_type)
        REGISTRY.register(LocustCollector(environment, runner))



class StoreWebUserV2(HttpUser):
    wait_time = between(1, 2)  # Wait between 1 and 2 seconds between tasks

    @task(50)
    def find_snaps_simple(self):
        headers = {
            "Snap-Device-Series": '16',
        }
        query_params = {
            "q": "postgres"
        }
        self.client.get("/v2/snaps/find", headers=headers, params=query_params)

    @task(5)
    def find_charms_simple(self):
        headers = {}
        query_params = {
            "q": "postgres"
        }
        self.client.get("/v2/charms/find", headers=headers, params=query_params)


#    @task(5)
#    def get_health(self):
#        expected_resp = {"database":"healthy"}
#        with self.client.get("/v1/health", catch_response=True) as resp:
#            if resp.json() != expected_resp:
#                resp.failure("Database is not healthy, please check DB metrics!")


#class StoreSnapdUser(HttpUser):
#    pass
