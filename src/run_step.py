"""Cloud Run job entrypoint: run ONE pipeline step, chosen by the STEP environment variable.

The workflow starts the same job several times and sets, per execution:
  STEP=bronze    BATCH_ID=<landed batch folder>    load that batch into bronze
  STEP=silver                                      build silver and run silver tests
  STEP=gold                                        build gold and run gold tests
  STEP=pipeline  (BATCH_ID optional)               all three in order
Using env vars (instead of overriding the container command) keeps the buildpack launcher in charge,
so Python and the installed libraries are on the path.
Locally you would just run the individual scripts.
"""
import os
import sys


def main() -> None:
    step = os.environ.get("STEP", "").strip().lower()
    batch_id = os.environ.get("BATCH_ID", "").strip() or None

    if step == "bronze":
        if not batch_id:
            sys.exit("STEP=bronze needs BATCH_ID (a folder under gs://<bucket>/landing/)")
        import load_bronze
        load_bronze.main(batch_id)
    elif step == "silver":
        import run_silver
        run_silver.main()
    elif step == "gold":
        import run_gold
        run_gold.main()
    elif step == "pipeline":
        import load_bronze
        import run_gold
        import run_silver
        load_bronze.main(batch_id)
        run_silver.main()
        run_gold.main()
    else:
        sys.exit(f"Unknown or missing STEP '{step}'. Use bronze, silver, gold or pipeline.")


if __name__ == "__main__":
    main()
