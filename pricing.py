import os
import logging
import random

logger = logging.getLogger()


seed = os.environ["SEED"]
seed = int(seed)
random.seed(seed)


def lambda_handler(event, context):
    logger.info("received processing event {!r}".format(event))

    # in pharmacy benefits, the prices are just made up
    return {
        "price": random.randint(1, 10000),
    }