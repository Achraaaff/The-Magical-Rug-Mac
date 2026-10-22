#pragma once
#include "Physics/cloth.hpp"

// Portable interaction layer. Screen coordinates use the Linux solver's
// top-left origin; the Cocoa adapter converts from macOS's bottom-left origin.
struct RugModel {
    enum class Mode { Idle, Move, Fold, Resize, Rotate };
    struct Bounds { float left, top, right, bottom; };
    Cloth cloth;
    float viewportWidth, viewportHeight;
    bool locked=false, folded=false, sleeping=true;
    Mode mode=Mode::Idle;
    int quiet=0, frames=0;
    V3 initialMouse, previousMouse, grabOffset;
    float initialGrabHeight=0, initialWidth=0;

    RugModel(float w, float h, float aspect=.67f):viewportWidth(w),viewportHeight(h) {
        float width=std::min(w*.46f,h*.78f/aspect);
        cloth.reset((w-width)/2,(h-width*aspect)/2,width,width*aspect);
    }
    V3 project(V3 p)const {
        float distance=std::max(viewportWidth,viewportHeight)*1.5f;
        float scale=distance/std::max(distance-p.z,distance*.4f);
        return {viewportWidth/2+(p.x-viewportWidth/2)*scale,
                viewportHeight/2+(p.y-viewportHeight/2)*scale,p.z};
    }
    V3 unproject(V3 p,float z)const {
        float distance=std::max(viewportWidth,viewportHeight)*1.5f;
        float scale=(distance-z)/distance;
        return {viewportWidth/2+(p.x-viewportWidth/2)*scale,
                viewportHeight/2+(p.y-viewportHeight/2)*scale,z};
    }
    Bounds bounds()const {
        Bounds b{1e9f,1e9f,-1e9f,-1e9f};
        for(auto p:cloth.pos){auto q=project(p);b.left=std::min(b.left,q.x);b.top=std::min(b.top,q.y);b.right=std::max(b.right,q.x);b.bottom=std::max(b.bottom,q.y);}
        return b;
    }
    int pick(V3 p)const {
        if(locked)return -1;
        auto box=bounds();if(p.x<box.left||p.y<box.top||p.x>box.right||p.y>box.bottom)return -1;
        float best=-1e9f;int found=-1;
        for(auto f:cloth.faces){
            auto a=project(cloth.pos[f[0]]),b=project(cloth.pos[f[1]]),c=project(cloth.pos[f[2]]);
            V3 u=b-a,v=c-a,d=p-a;float determinant=u.x*v.y-v.x*u.y;
            if(std::abs(determinant)<1e-6f)continue;
            float s=(d.x*v.y-v.x*d.y)/determinant,t=(u.x*d.y-d.x*u.y)/determinant,w=1-s-t;
            if(s<0||t<0||w<0)continue;
            float z=cloth.pos[f[0]].z*w+cloth.pos[f[1]].z*s+cloth.pos[f[2]].z*t;
            if(z>best){best=z;found=w>=s&&w>=t?f[0]:s>=t?f[1]:f[2];}
        }
        return found;
    }
    void wake(){if(!locked){sleeping=false;quiet=0;frames=0;}}
    void pause(){cloth.end();for(auto &v:cloth.vel)v={};mode=Mode::Idle;sleeping=true;}
    void setLocked(bool value){if(locked==value)return;pause();locked=value;}
    bool press(V3 p,bool resize=false,bool rotate=false){
        int v=pick(p);if(v<0)return false;
        initialMouse=previousMouse=p;initialWidth=cloth.rw;
        int x=v%cloth.nx,y=v/cloth.nx;
        if(resize){mode=Mode::Resize;cloth.end();sleeping=true;}
        else if(rotate){mode=Mode::Rotate;cloth.end();sleeping=true;}
        else if(x<2||x>=cloth.nx-2||y<2||y>=cloth.ny-2){
            mode=Mode::Fold;initialGrabHeight=std::max(0.f,cloth.pos[v].z);
            grabOffset=cloth.pos[v]-unproject(p,initialGrabHeight);
            cloth.begin(v,cloth.pos[v]);wake();
        }else {mode=Mode::Move;cloth.end();sleeping=true;}
        return true;
    }
    void drag(V3 p){
        if(locked||mode==Mode::Idle)return;
        auto delta=p-previousMouse;previousMouse=p;
        if(mode==Mode::Move){
            auto b=bounds();
            float minX=2-b.left,maxX=viewportWidth-b.right-2,minY=2-b.top,maxY=viewportHeight-b.bottom-2;
            cloth.translate(minX<=maxX?std::clamp(delta.x,minX,maxX):0,minY<=maxY?std::clamp(delta.y,minY,maxY):0);
        }else if(mode==Mode::Fold){
            float distance=std::hypot(p.x-initialMouse.x,p.y-initialMouse.y);
            float peak=std::min(cloth.rw,cloth.rh)*.205f;
            float arc=std::min(distance*.9f,std::max(cloth.thickness*1.5f,peak-std::max(0.f,distance-peak*1.36f)*.65f));
            cloth.grabTarget=unproject(p,initialGrabHeight+arc)+grabOffset;
        }else if(mode==Mode::Resize){
            float desired=std::clamp(1+(p.x-initialMouse.x)/std::max(300.f,initialWidth),.5f,1.8f);
            resize(initialWidth*desired/cloth.rw);
        }else if(mode==Mode::Rotate){cloth.rotate(delta.x*.006f);}
    }
    void release(){
        if(locked)return;bool lifted=mode==Mode::Fold;cloth.end();mode=Mode::Idle;
        if(lifted){folded=true;wake();}
    }
    void rotate(float angle){if(!locked){cloth.rotate(angle);}}
    void resize(float factor){
        if(locked||cloth.rw*factor<240||cloth.rh*factor<140||cloth.rw*factor>viewportWidth*.94f||cloth.rh*factor>viewportHeight*.94f)return;
        cloth.scale(factor);
    }
    void flatten(){
        if(locked)return;auto center=cloth.center();
        cloth.reset(center.x-cloth.rw/2,center.y-cloth.rh/2,cloth.rw,cloth.rh);
        folded=false;pause();keepOnScreen();
    }
    void toggleFold(){if(locked)return;if(folded){flatten();return;}cloth.foldCorner();folded=true;wake();}
    void center(){if(locked)return;auto c=cloth.center();cloth.translate(viewportWidth/2-c.x,viewportHeight/2-c.y);}
    void keepOnScreen(){
        auto b=bounds();float dx=0,dy=0;
        if(b.left<2)dx=2-b.left;else if(b.right>viewportWidth-2)dx=viewportWidth-2-b.right;
        if(b.top<2)dy=2-b.top;else if(b.bottom>viewportHeight-2)dy=viewportHeight-2-b.bottom;
        cloth.translate(dx,dy);
    }
    bool restore(float w,float h,float oldViewW,float oldViewH,const std::vector<V3>&points,bool savedLocked,bool savedFolded){
        if(!std::isfinite(w+h+oldViewW+oldViewH)||w<240||h<140||w>4000||h>3000||oldViewW<300||oldViewH<200)return false;
        Cloth restored;restored.reset(0,0,w,h);if(points.size()!=size_t(restored.count()))return false;
        for(auto p:points)if(!std::isfinite(p.x+p.y+p.z)||std::abs(p.x)>20000||std::abs(p.y)>20000||p.z<0||p.z>1500)return false;
        restored.pos=points;if(restored.maxStructuralStretch()>1.35f)return false;
        auto c=restored.center();float scale=std::min({1.f,viewportWidth*.9f/w,viewportHeight*.9f/h});
        float cx=std::clamp(c.x/oldViewW,0.f,1.f)*viewportWidth,cy=std::clamp(c.y/oldViewH,0.f,1.f)*viewportHeight;
        restored.reset(0,0,w*scale,h*scale);if(points.size()!=size_t(restored.count()))return false;
        for(int i=0;i<restored.count();i++){restored.pos[i]={cx+(points[i].x-c.x)*scale,cy+(points[i].y-c.y)*scale,points[i].z*scale};restored.prev[i]=restored.pos[i];}
        restored.derive();cloth=std::move(restored);locked=savedLocked;folded=savedFolded;pause();keepOnScreen();return true;
    }
    void setViewport(float width,float height){
        auto saved=cloth.pos;float w=cloth.rw,h=cloth.rh,oldW=viewportWidth,oldH=viewportHeight;
        viewportWidth=width;viewportHeight=height;
        restore(w,h,oldW,oldH,saved,locked,folded);
    }
    void step(float dt){
        if(locked||sleeping)return;
        cloth.step(std::clamp(dt,1.f/120,1.f/30));frames++;
        if(!std::isfinite(cloth.maxSpeed)){float width=viewportWidth*.46f,height=width*.67f;cloth.reset((viewportWidth-width)/2,(viewportHeight-height)/2,width,height);folded=false;pause();return;}
        if(mode==Mode::Idle){quiet=cloth.rmsSpeed<6?quiet+1:0;if(quiet>16||(frames>240&&cloth.rmsSpeed<35)){pause();}}
    }
};
