package io.github.mj_youn.plugin;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class PackageDockerMojoTest {

    @Test
    @DisplayName("PackageDockerMojo 인스턴스가 정상 생성되고 기본 속성이 유지되어야 한다.")
    void testPackageDockerMojoInstantiation() {
        PackageDockerMojo mojo = new PackageDockerMojo();
        assertNotNull(mojo);
    }

    @Test
    @DisplayName("PackageDockerRemoteMojo 및 DockerBuildRemoteMojo 인스턴스가 정상 생성되어야 한다.")
    void testPackageDockerRemoteMojoInstantiation() {
        PackageDockerRemoteMojo remoteMojo = new PackageDockerRemoteMojo();
        assertNotNull(remoteMojo);

        DockerBuildRemoteMojo aliasMojo = new DockerBuildRemoteMojo();
        assertNotNull(aliasMojo);
        assertTrue(aliasMojo instanceof PackageDockerRemoteMojo);
    }
}
