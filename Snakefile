from snakemake.shell import shell

shell.exec("bash")

python_versions = config["python_versions"]

wildcard_constraints:
    package = config["package"],
    version_number = config["version_number"]


rule run_tests:
    output:
        "{prefix}/test_ran_{version_number}"
    shell:
        "pytest -n 48 tests/ && touch {output[0]}"


rule create_sdist:
    input:
        "{prefix}/test_ran_{version_number}"
    output:
        "dist/{package}_{version_number}.tar.gz"
    shell:
        "python setup.py sdist"

rule create_wheels_linux_script:
    output:
        "{prefix}/script.sh"
    run:
        script = """for PYBIN in /opt/python/*3[5-7]*/bin; do
"${PYBIN}/pip" wheel /io/ -w wheelhouse/
done

for whl in wheelhouse/*.whl; do
auditwheel repair "$whl" -w /io/wheelhouse/
done"""

        open(output[0], "w+").write(script)


from subprocess import check_output, call


rule create_wheels_manylinux:
    "If this fails, run  'docker pull quay.io/pypa/manylinux1_x86_64' first"
    input:
        script = "{prefix}/script.sh"
        dummy = "{prefix}/test_ran_{version_number}"
    output:
        "wheelhouse/{package_name}-{version_number}-{python_version}-{python-version}m-manylinux1_x86_64.whl"
    run:
        container = check_output("docker run -d -it -v $(pwd):/io quay.io/pypa/manylinux1_x86_64", shell=True).decode()
        call(f"docker cp {input.script} {container}:script.sh", shell=True)
        call(f"docker exec {container} sh script.sh", shell=True)
        call(f"docker stop {container}", shell=True)


rule create_wheels_macos:
    input:
        dummy = "{prefix}/test_ran_{version_number}"
    output:
        "dist/{package_name}-{version_number}-{python_version}-{python-version}m-manylinux1_x86_64.whl"
        # ncls-0.0.30-cp36-cp36m-macosx_10_7_x86_64.whl
