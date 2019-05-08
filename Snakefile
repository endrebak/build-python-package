from snakemake.shell import shell

shell.executable("bash")

python_versions = config["linux_wheel_python_versions"]

prefix = config["prefix"]
version_number = config["version_number"]
package = config["package"]
requirements_host = config["bioconda_dependencies"]["host"]
requirements_run = config["bioconda_dependencies"]["run"]


# commands:
# - {test_command}


wildcard_constraints:
    package = package,
    version_number = version_number


linux_wheels = expand("{prefix}/{package}_{version_number}_{python_version}_uploaded_wheel",
                        prefix=prefix, package=package, version_number=version_number,
                        python_version=python_versions)
sdist = f"{prefix}/{package}_{version_number}_uploaded_sdist",

create = [sdist]


if config["linux_wheels"]:
    create.extend(linux_wheels)

if config["bioconda"]:
    bioconda_file = f"{prefix}/{package}-{version_number}/meta.yaml"
    create.append(bioconda_file)


rule all:
    input:
        create


rule create_sdist:
    # input:
    #     prefix + "/test_ran_{version_number}"
    output:
        "dist/{package}-{version_number}.tar.gz"
    shell:
        "python setup.py sdist"

rule create_wheels_linux_script:
    output:
        "{prefix}/script.sh"
    run:
        script = """for PYBIN in /opt/python/*3[5-7]*/bin; do
"${PYBIN}/pip" install cython numpy  # install these requirements first
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
        script = prefix + "/script.sh",
        # dummy = "{prefix}/test_ran_{version_number}"
    output:
        expand("wheelhouse/{{package_name}}-{{version_number}}-{python_version}-{python_version}m-manylinux1_x86_64.whl",
               python_version=python_versions)
    run:
        container = check_output("docker run -d -it -v $(pwd):/io quay.io/pypa/manylinux1_x86_64", shell=True).decode().strip()
        print(f"docker cp {input.script} {container}:script.sh")
        call(f"docker cp {input.script} {container}:script.sh", shell=True)
        call(f"docker exec {container} sh script.sh", shell=True)
        call(f"docker stop {container}", shell=True)


rule upload_sdist:
    "requires a ~/.pypirc"
    input:
        "dist/{package}-{version_number}.tar.gz"
    output:
        "{prefix}/{package}_{version_number}_uploaded_sdist"
    shell:
        "twine upload {input[0]}"


rule upload_wheel:
    "requires a ~/.pypirc"
    input:
        "wheelhouse/{package}-{version_number}-{python_version}-{python_version}m-manylinux1_x86_64.whl"
    output:
        prefix + "/{package}_{version_number}_{python_version}_uploaded_wheel"
    shell:
        "twine upload {input[0]} && touch {output}"


rule get_sha_256:
    input:
        "dist/{package}-{version_number}.tar.gz"
    output:
        "{prefix}/{package}-{version_number}_sha256.txt"
    shell:
        "shasum -a 256 {input[0]} | cut -f 1 -d ' ' > {output[0]}"


rule get_pypi_sdist_link:
    input:
        dummy = "{prefix}/{package}_{version_number}_uploaded_sdist"
    output:
        "{prefix}/{package}_{version_number}_sdist_link.txt"
    run:
        url = "https://pypi.org/project/{package}/{version_number}/".format(**wildcards)

        import urllib.request
        with urllib.request.urlopen(url) as response:
            html = response.read()

        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "lxml")

        links = [tag.get("href") for tag in soup.find_all('a') if not tag.get("href") is None]

        package, version_number = wildcards.package, wildcards.version_number
        link = [link for link in links if link.endswith(f"{package}-{version_number}.tar.gz")][0]

        open(output[0], "w+").write(link)


rule create_bioconda_yaml:
    input:
        sdist_link = "{prefix}/{package}_{version_number}_sdist_link.txt",
        sha256 = "{prefix}/{package}-{version_number}_sha256.txt"
    output:
        "{prefix}/{package}-{version_number}/meta.yaml"
    run:
        url = open(input.sdist_link).readline().strip()
        sha256 = open(input.sha256).readline().strip()
        # to put in locals
        reqs_run = "\n".join(["-" + r for r in requirements_run])
        reqs_host = "\n".join(["-" + r for r in requirements_host])
        # requirements_run = requirements_run
        # requirements_host = requirements_host
        locals().update(wildcards)
        locals().update(config)
        bioconda_template = """package:
  name: {package}
  version: "{version_number}"

source:
  url: {url}
  sha256: {sha256}

build:
  number: 0
  skip:
    True # [osx]

requirements:
  host:
    {reqs_host}

  run:
    {reqs_run}

test:
  # Python imports
  imports:
    - {package}

about:
home: {home}
license: {license}
summary: '{summary}'""".format(**locals())

        print(bioconda_template)



# rule get_bioconda_yaml:
#     output:
#         "{prefix}/{package}_{version_number}_bioconda.yaml"
#     run:
        # url = "https://raw.githubusercontent.com/bioconda/bioconda-recipes/master/recipes/{package}/meta.yaml".format(**wildcards)

        # import urllib.request
        # with urllib.request.urlopen(url) as response:
        #     html = response.read()

        # import yaml
        # d = yaml.load(html)








# rule create_wheels_macos:
    # input:
    #     dummy = "{prefix}/test_ran_{version_number}"
    # output:
    #     "dist/{package_name}-{version_number}-{python_version}-{python-version}m-manylinux1_x86_64.whl"
        # ncls-0.0.30-cp36-cp36m-macosx_10_7_x86_64.whl
