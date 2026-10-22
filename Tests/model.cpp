#include "../Sources/RugModel.hpp"
#include "intersection.hpp"
#include "visible-back.hpp"
#include <iostream>
#include <cstdlib>
#include <limits>
void check(bool value,const char *message){if(!value){std::cerr<<"FAIL: "<<message<<std::endl;std::exit(1);}}
bool same(const std::vector<V3>&a,const std::vector<V3>&b){if(a.size()!=b.size())return false;for(size_t i=0;i<a.size();i++)if((a[i]-b[i]).len()>1e-5)return false;return true;}
void foldCorner(int corner){
    RugModel m(1920,1080);auto &c=m.cloth;
    int index=corner==0?0:corner==1?c.nx-1:corner==2?c.nx*(c.ny-1):c.count()-1;
    int opposite=c.count()-1-index;auto original=c.pos;
    float sx=(corner==0||corner==2)?1:-1,sy=corner<2?1:-1;
    auto start=c.pos[index]+V3{sx*5,sy*5,0};check(m.press(start),"couldn't grab corner");
    for(int i=0;i<8;i++)m.step(1.f/60);check(same(c.pos,original),"press jumped before dragging");
    float stretch=1;int crossing=0;
    for(int f=0;f<240;f++){float t=f/239.f;m.drag(start+V3{sx*300*t,sy*220*t,0});m.step(1.f/60);stretch=std::max(stretch,c.maxStructuralStretch());if(f%30==0)crossing=std::max(crossing,intersections(c));}
    m.release();for(int f=0;f<300;f++)m.step(1.f/60);
    int visible=visibleBack(c);crossing=std::max(crossing,intersections(c));
    std::cout<<"Corner "<<corner<<": visible underside on top="<<visible<<", crossings="<<crossing<<", max stretch="<<stretch<<", far drift="<<(c.pos[opposite]-original[opposite]).len()<<std::endl;
    check(visible>30,"fold tucked underneath or sprang flat");check(crossing==0,"cloth passed through itself");check(stretch<1.3,"cloth stretched into strips");check((c.pos[opposite]-original[opposite]).len()<8,"fold moved the whole rug");
    m.flatten();check(visibleBack(c)==0,"flatten left a reversed flap");
}
int main(){
    RugModel m(1440,900);auto center=m.cloth.center();auto original=m.cloth.pos;
    check(m.press(center),"body not interactive");m.drag(center+V3{50,30,0});check(!same(original,m.cloth.pos),"middle dragging didn't move directly");m.setLocked(true);
    auto frozen=m.cloth.pos;check(m.pick(center)<0,"locked hit test didn't pass through");
    m.drag(center+V3{300,100,0});m.release();m.toggleFold();m.flatten();m.rotate(1);m.resize(1.1);m.center();for(int f=0;f<30;f++)m.step(1.f/60);
    check(same(frozen,m.cloth.pos)&&m.sleeping,"lock allowed movement");
    RugModel restored(1440,900);check(restored.restore(m.cloth.rw,m.cloth.rh,1440,900,frozen,true,false),"saved pose restore failed");check(restored.locked&&same(frozen,restored.cloth.pos),"lock or shape wasn't retained");
    restored.setLocked(false);check(restored.press(restored.cloth.center()),"unlock didn't restore input");restored.drag(restored.cloth.center()+V3{20,20,0});restored.release();
    auto invalid=frozen;invalid[0].z=std::numeric_limits<float>::quiet_NaN();check(!restored.restore(m.cloth.rw,m.cloth.rh,1440,900,invalid,false,false),"invalid saved pose accepted");
    m.setViewport(1280,800);check(m.locked,"display resize lost lock");check(m.cloth.maxStructuralStretch()<1.01,"display resize distorted material");
    for(int i=0;i<4;i++)foldCorner(i);
    std::cout<<"PASS: direct movement, silent lock, saved state, display changes, outward folds and layer separation."<<std::endl;
}
